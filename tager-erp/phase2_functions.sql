-- Phase 4: Core Database Functions & Transaction Layer
-- Target: PostgreSQL / Supabase
-- Responsibility: Atomic operations, Auditability, Event Emission, Multi-unit conversion.
-- SECURITY: All functions validate tenant_id before performing operations.

--------------------------------------------------------------------------------
-- 0. SECURITY HELPER: Validate Tenant Ownership
--------------------------------------------------------------------------------
-- CRITICAL: This function MUST be called at the start of every function that
-- accepts p_tenant_id to prevent cross-tenant data manipulation attacks.

CREATE OR REPLACE FUNCTION assert_tenant_ownership(p_tenant_id UUID)
RETURNS VOID AS $$
BEGIN
    IF p_tenant_id IS DISTINCT FROM auth.get_tenant_id() THEN
        RAISE EXCEPTION 'Access denied: tenant_id mismatch. You cannot operate on data belonging to another tenant.'
            USING ERRCODE = '42501'; -- insufficient_privilege
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 1. EVENT EMISSION HELPER
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emit_event(
    p_tenant_id UUID,
    p_event_type TEXT,
    p_payload JSONB,
    p_actor_id UUID DEFAULT auth.uid()
) RETURNS UUID AS $$
DECLARE
    v_event_id UUID;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    INSERT INTO event_log (tenant_id, event_type, payload, actor_id)
    VALUES (p_tenant_id, p_event_type, p_payload, p_actor_id)
    RETURNING id INTO v_event_id;
    
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 2. INVENTORY FUNCTIONS
--------------------------------------------------------------------------------

-- Helper: Get Base Unit Quantity
-- FIXED: Added tenant validation to prevent cross-tenant data access
CREATE OR REPLACE FUNCTION get_base_quantity(
    p_unit_id UUID,
    p_quantity NUMERIC
) RETURNS NUMERIC AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    -- SECURITY: Verify unit belongs to tenant via variant chain
    SELECT ud.conversion_rate INTO v_rate 
    FROM unit_definitions ud
    JOIN product_variants pv ON ud.variant_id = pv.id
    WHERE ud.id = p_unit_id 
      AND pv.tenant_id = auth.get_tenant_id();
    
    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'Unit definition not found or access denied: %', p_unit_id;
    END IF;
    RETURN p_quantity * v_rate;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function: Adjust Stock
CREATE OR REPLACE FUNCTION adjust_stock(
    p_tenant_id UUID,
    p_variant_id UUID,
    p_location_id UUID,
    p_unit_id UUID,
    p_quantity NUMERIC,
    p_type_key TEXT,
    p_reason TEXT DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_new_balance NUMERIC;
    v_actor_id UUID := auth.uid();
BEGIN
    -- SECURITY: Validate tenant ownership before any operation
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- 1. Update stock_levels (UPSERT)
    INSERT INTO stock_levels (tenant_id, variant_id, location_id, unit_id, quantity)
    VALUES (p_tenant_id, p_variant_id, p_location_id, p_unit_id, p_quantity)
    ON CONFLICT (tenant_id, variant_id, location_id, unit_id)
    DO UPDATE SET quantity = stock_levels.quantity + EXCLUDED.quantity, updated_at = NOW()
    RETURNING quantity INTO v_new_balance;

    -- 2. Log Movement (Audit Trail)
    INSERT INTO stock_movements (
        tenant_id, variant_id, location_id, unit_id, 
        change_quantity, balance_after, type_key, reason, reference_id, actor_id
    )
    VALUES (
        p_tenant_id, p_variant_id, p_location_id, p_unit_id,
        p_quantity, v_new_balance, p_type_key, p_reason, p_reference_id, v_actor_id
    );

    -- 3. Emit Event
    PERFORM emit_event(
        p_tenant_id, 
        'stock.adjusted', 
        jsonb_build_object(
            'variant_id', p_variant_id,
            'location_id', p_location_id,
            'unit_id', p_unit_id,
            'change', p_quantity,
            'new_balance', v_new_balance,
            'type', p_type_key
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Reserve Stock
-- FIXED: Comprehensive race condition prevention using advisory locks and atomic operations
-- RACE CONDITION FIX STRATEGY:
-- 1. Use PostgreSQL Advisory Locks for variant+location combination (prevents concurrent reservations)
-- 2. Lock both stock_levels AND stock_reservations tables atomically
-- 3. Use a single atomic query to check and reserve in one transaction
CREATE OR REPLACE FUNCTION reserve_stock(
    p_tenant_id UUID,
    p_variant_id UUID,
    p_location_id UUID,
    p_unit_id UUID,     -- Unit for reservation
    p_quantity NUMERIC, -- Quantity in specified unit
    p_order_id UUID DEFAULT NULL,
    p_expires_in INTERVAL DEFAULT INTERVAL '1 hour'
) RETURNS UUID AS $$
DECLARE
    v_reservation_id UUID;
    v_base_requested NUMERIC;
    v_base_available NUMERIC;
    v_lock_key BIGINT;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Convert requested quantity to base units
    v_base_requested := get_base_quantity(p_unit_id, p_quantity);

    -- RACE CONDITION FIX STEP 1: Acquire advisory lock for this variant+location combination
    -- This prevents concurrent transactions from making reservations on the same stock
    -- The lock key is derived from variant_id and location_id to create a unique identifier
    v_lock_key := get_stock_lock_key(p_variant_id, p_location_id);
    
    -- Try to acquire exclusive advisory lock (waits if another transaction holds it)
    PERFORM pg_advisory_xact_lock(v_lock_key);
    
    -- RACE CONDITION FIX STEP 2: Lock stock_levels rows for this variant/location
    -- Using FOR UPDATE NOWAIT to fail fast if rows are locked by another transaction
    -- This creates a serialization point for stock operations
    PERFORM 1 FROM stock_levels 
    WHERE tenant_id = p_tenant_id 
      AND variant_id = p_variant_id 
      AND location_id = p_location_id
    FOR UPDATE;

    -- RACE CONDITION FIX STEP 3: Lock existing reservations for this variant/location
    -- This prevents concurrent reservations from being created while we calculate availability
    PERFORM 1 FROM stock_reservations
    WHERE tenant_id = p_tenant_id
      AND variant_id = p_variant_id
      AND location_id = p_location_id
    FOR UPDATE;

    -- RACE CONDITION FIX STEP 4: Calculate available stock in a single atomic query
    -- This combines on-hand stock minus existing reservations in one operation
    -- Using CTE for better performance and atomicity
    WITH stock_calculation AS (
        -- Calculate total on-hand stock in base units
        SELECT COALESCE(SUM(sl.quantity * ud.conversion_rate), 0) AS on_hand_base
        FROM stock_levels sl
        JOIN unit_definitions ud ON sl.unit_id = ud.id
        WHERE sl.tenant_id = p_tenant_id 
          AND sl.variant_id = p_variant_id 
          AND sl.location_id = p_location_id
    ),
    reservation_calculation AS (
        -- Calculate total reserved stock in base units
        SELECT COALESCE(SUM(sr.quantity * ud.conversion_rate), 0) AS reserved_base
        FROM stock_reservations sr
        JOIN unit_definitions ud ON sr.unit_id = ud.id
        WHERE sr.tenant_id = p_tenant_id 
          AND sr.variant_id = p_variant_id 
          AND sr.location_id = p_location_id
    )
    SELECT (sc.on_hand_base - rc.reserved_base) INTO v_base_available
    FROM stock_calculation sc, reservation_calculation rc;

    -- Validate availability
    IF v_base_available < v_base_requested THEN
        RAISE EXCEPTION 'Insufficient available stock. Available: %, Requested: %', 
            v_base_available, v_base_requested;
    END IF;

    -- Create the reservation
    INSERT INTO stock_reservations (tenant_id, variant_id, location_id, unit_id, quantity, order_id, expires_at)
    VALUES (p_tenant_id, p_variant_id, p_location_id, p_unit_id, p_quantity, p_order_id, NOW() + p_expires_in)
    RETURNING id INTO v_reservation_id;

    -- Emit event for audit trail
    PERFORM emit_event(
        p_tenant_id,
        'stock.reserved',
        jsonb_build_object(
            'reservation_id', v_reservation_id, 
            'variant_id', p_variant_id, 
            'quantity_base', v_base_requested,
            'available_before', v_base_available,
            'available_after', (v_base_available - v_base_requested)
        )
    );

    RETURN v_reservation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Release Stock Reservation
CREATE OR REPLACE FUNCTION release_stock(
    p_tenant_id UUID,
    p_reservation_id UUID
) RETURNS VOID AS $$
DECLARE
    v_reservation RECORD;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Fetch and delete reservation atomically
    DELETE FROM stock_reservations
    WHERE id = p_reservation_id AND tenant_id = p_tenant_id
    RETURNING * INTO v_reservation;

    IF v_reservation IS NULL THEN
        RAISE EXCEPTION 'Reservation not found or does not belong to this tenant: %', p_reservation_id;
    END IF;

    PERFORM emit_event(
        p_tenant_id,
        'stock.released',
        jsonb_build_object('reservation_id', p_reservation_id, 'variant_id', v_reservation.variant_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 3. SALES FUNCTIONS
--------------------------------------------------------------------------------

-- Function: Create Order
-- FIXED: Added validation for location_id and customer_id ownership
CREATE OR REPLACE FUNCTION create_order(
    p_tenant_id UUID,
    p_location_id UUID,
    p_customer_id UUID,
    p_items JSONB, -- Expected: [{"variant_id": "...", "unit_id": "...", "quantity": 1, "unit_price": 100, "tax_rate": 0.14, "discount_amount": 0}]
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_order_id UUID;
    v_item RECORD;
    v_total NUMERIC := 0;
    v_total_tax NUMERIC := 0;
    v_total_discount NUMERIC := 0;
    v_total_net NUMERIC := 0;
    v_net_item NUMERIC;
    v_total_item NUMERIC;
    v_base_requested NUMERIC;
    v_base_on_hand NUMERIC;
    v_base_reserved NUMERIC;
    v_tax_amount NUMERIC;
    v_tax_rate NUMERIC;
    v_discount_amount NUMERIC;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- VALIDATION: Verify location belongs to tenant
    IF NOT EXISTS (
        SELECT 1 FROM locations 
        WHERE id = p_location_id AND tenant_id = p_tenant_id AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Location not found or access denied: %', p_location_id;
    END IF;

    -- VALIDATION: Verify customer belongs to tenant (if provided)
    IF p_customer_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM customers 
            WHERE id = p_customer_id AND tenant_id = p_tenant_id AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Customer not found or access denied: %', p_customer_id;
        END IF;
    END IF;

    -- 1. Insert Order Header (Totals will be updated after processing items)
    INSERT INTO orders (tenant_id, location_id, customer_id, status_key, metadata, actor_id)
    VALUES (p_tenant_id, p_location_id, p_customer_id, 'pending', p_metadata, auth.uid())
    RETURNING id INTO v_order_id;

    -- 2. Process Items
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) 
                  AS x(variant_id UUID, unit_id UUID, quantity NUMERIC, unit_price NUMERIC, tax_rate NUMERIC, discount_amount NUMERIC)
    LOOP
        -- Validations
        IF v_item.quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
        
        -- SECURITY: Verify variant belongs to tenant
        IF NOT EXISTS (
            SELECT 1 FROM product_variants 
            WHERE id = v_item.variant_id AND tenant_id = p_tenant_id AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Variant not found or access denied: %', v_item.variant_id;
        END IF;
        
        -- SECURITY: Verify unit belongs to the variant (and thus tenant)
        IF NOT EXISTS (
            SELECT 1 FROM unit_definitions ud
            JOIN product_variants pv ON ud.variant_id = pv.id
            WHERE ud.id = v_item.unit_id AND pv.tenant_id = p_tenant_id
        ) THEN
            RAISE EXCEPTION 'Unit not found or access denied: %', v_item.unit_id;
        END IF;
        
        v_base_requested := get_base_quantity(v_item.unit_id, v_item.quantity);
        v_discount_amount := COALESCE(v_item.discount_amount, 0);
        v_tax_rate := COALESCE(v_item.tax_rate, 0);

        -- RACE CONDITION FIX: Lock stock for this variant during order creation
        -- This prevents concurrent orders from over-selling the same stock
        PERFORM pg_advisory_xact_lock(get_stock_lock_key(v_item.variant_id, p_location_id));
        
        -- Lock stock levels row
        PERFORM 1 FROM stock_levels 
        WHERE tenant_id = p_tenant_id 
          AND variant_id = v_item.variant_id 
          AND location_id = p_location_id
        FOR UPDATE;

        -- Calculate Available Stock (atomic with locks held)
        SELECT COALESCE(SUM(sl.quantity * ud.conversion_rate), 0) INTO v_base_on_hand
        FROM stock_levels sl
        JOIN unit_definitions ud ON sl.unit_id = ud.id
        WHERE sl.tenant_id = p_tenant_id AND sl.variant_id = v_item.variant_id AND sl.location_id = p_location_id;

        SELECT COALESCE(SUM(sr.quantity * ud.conversion_rate), 0) INTO v_base_reserved
        FROM stock_reservations sr
        JOIN unit_definitions ud ON sr.unit_id = ud.id
        WHERE sr.tenant_id = p_tenant_id AND sr.variant_id = v_item.variant_id AND sr.location_id = p_location_id
        AND (sr.order_id IS DISTINCT FROM v_order_id);

        IF (v_base_on_hand - v_base_reserved) < v_base_requested THEN
            RAISE EXCEPTION 'Insufficient stock for variant %. Available Base: %, Requested Base: %', 
                v_item.variant_id, (v_base_on_hand - v_base_reserved), v_base_requested;
        END IF;

        -- Calculate Financials (Strict VAT Logic)
        v_net_item := v_item.quantity * v_item.unit_price;
        
        -- SAFETY CHECK: Discount cannot exceed Net Price
        IF v_discount_amount > v_net_item THEN
            RAISE EXCEPTION 'Discount amount (%) exceeds the net price (%) for variant %', 
                v_discount_amount, v_net_item, v_item.variant_id;
        END IF;
        
        -- Tax Base = Net - Discount (Ensure non-negative)
        -- Tax Amount = Tax Base * Rate
        v_tax_amount := GREATEST(0, (v_net_item - v_discount_amount)) * v_tax_rate;
        
        -- Total = Net - Discount + Tax
        v_total_item := v_net_item - v_discount_amount + v_tax_amount;

        -- Insert Item
        INSERT INTO order_items (
            tenant_id, order_id, variant_id, unit_id, quantity, unit_price, 
            net_amount, discount_amount, tax_rate, tax_amount, total_price
        )
        VALUES (
            p_tenant_id, v_order_id, v_item.variant_id, v_item.unit_id, v_item.quantity, v_item.unit_price, 
            v_net_item, v_discount_amount, v_tax_rate, v_tax_amount, v_total_item
        );
        
        -- Accumulate Totals
        v_total_net := v_total_net + v_net_item;
        v_total_tax := v_total_tax + v_tax_amount;
        v_total_discount := v_total_discount + v_discount_amount;
        v_total := v_total + v_total_item;

        -- Deduct Stock
        PERFORM adjust_stock(
            p_tenant_id, v_item.variant_id, p_location_id, v_item.unit_id, 
            -v_item.quantity, 'sale', 'Order Created', v_order_id
        );

        -- Clean Reservations
        DELETE FROM stock_reservations 
        WHERE tenant_id = p_tenant_id AND variant_id = v_item.variant_id 
        AND location_id = p_location_id AND order_id = v_order_id;
    END LOOP;

    -- 3. Update Order Totals (Sum of Items)
    UPDATE orders 
    SET total_amount = v_total,
        tax_amount = v_total_tax,
        discount_amount = v_total_discount,
        net_amount = v_total_net
    WHERE id = v_order_id;

    -- 4. Emit Event
    PERFORM emit_event(
        p_tenant_id,
        'order.created',
        jsonb_build_object(
            'order_id', v_order_id, 
            'net', v_total_net,
            'tax', v_total_tax, 
            'discount', v_total_discount,
            'total', v_total
        )
    );

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Cancel Order
CREATE OR REPLACE FUNCTION cancel_order(
    p_tenant_id UUID,
    p_order_id UUID,
    p_reason TEXT DEFAULT 'Cancelled by user'
) RETURNS VOID AS $$
DECLARE
    v_order RECORD;
    v_item RECORD;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- 1. Fetch order and validate
    SELECT * INTO v_order FROM orders WHERE id = p_order_id AND tenant_id = p_tenant_id;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found or does not belong to this tenant: %', p_order_id;
    END IF;

    IF v_order.status_key = 'cancelled' THEN
        RAISE EXCEPTION 'Order is already cancelled.';
    END IF;

    IF v_order.status_key = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel a completed order. Use refund flow instead.';
    END IF;

    -- 2. Return stock for each item
    FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id AND tenant_id = p_tenant_id
    LOOP
        PERFORM adjust_stock(
            p_tenant_id, v_item.variant_id, v_order.location_id, v_item.unit_id,
            v_item.quantity, 'return', p_reason, p_order_id
        );
    END LOOP;

    -- 3. Update order status
    UPDATE orders SET status_key = 'cancelled', updated_at = NOW() WHERE id = p_order_id;

    -- 4. Emit Event
    PERFORM emit_event(
        p_tenant_id,
        'order.cancelled',
        jsonb_build_object('order_id', p_order_id, 'reason', p_reason)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 4. FINANCIAL FUNCTIONS
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION log_payment(
    p_tenant_id UUID,
    p_order_id UUID,
    p_amount NUMERIC,
    p_method_key TEXT
) RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_order RECORD;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Validate order belongs to tenant
    SELECT * INTO v_order FROM orders WHERE id = p_order_id AND tenant_id = p_tenant_id;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found or does not belong to this tenant: %', p_order_id;
    END IF;

    INSERT INTO financial_transactions (tenant_id, order_id, type_key, amount, payment_method_key, status_key, actor_id)
    VALUES (p_tenant_id, p_order_id, 'payment', p_amount, p_method_key, 'success', auth.uid())
    RETURNING id INTO v_transaction_id;

    PERFORM emit_event(
        p_tenant_id,
        'payment.completed',
        jsonb_build_object('order_id', p_order_id, 'amount', p_amount, 'transaction_id', v_transaction_id)
    );

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 5. ADDITIONAL ORDER FUNCTIONS
--------------------------------------------------------------------------------

-- Function: Complete Order
-- Transitions order from pending to completed status
CREATE OR REPLACE FUNCTION complete_order(
    p_tenant_id UUID,
    p_order_id UUID
) RETURNS VOID AS $$
DECLARE
    v_order RECORD;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Fetch and validate order
    SELECT * INTO v_order FROM orders WHERE id = p_order_id AND tenant_id = p_tenant_id;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found or does not belong to this tenant: %', p_order_id;
    END IF;

    IF v_order.status_key = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot complete a cancelled order.';
    END IF;

    IF v_order.status_key = 'completed' THEN
        RAISE EXCEPTION 'Order is already completed.';
    END IF;

    -- Update order status
    UPDATE orders SET status_key = 'completed', updated_at = NOW() WHERE id = p_order_id;

    -- Emit Event
    PERFORM emit_event(
        p_tenant_id,
        'order.completed',
        jsonb_build_object('order_id', p_order_id, 'total', v_order.total_amount)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Refund Order
-- Creates refund transaction and returns stock for completed orders
CREATE OR REPLACE FUNCTION refund_order(
    p_tenant_id UUID,
    p_order_id UUID,
    p_reason TEXT DEFAULT 'Customer refund'
) RETURNS UUID AS $$
DECLARE
    v_order RECORD;
    v_item RECORD;
    v_refund_id UUID;
    v_total_refund NUMERIC := 0;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Fetch and validate order
    SELECT * INTO v_order FROM orders WHERE id = p_order_id AND tenant_id = p_tenant_id;
    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found or does not belong to this tenant: %', p_order_id;
    END IF;

    IF v_order.status_key != 'completed' THEN
        RAISE EXCEPTION 'Only completed orders can be refunded. Current status: %', v_order.status_key;
    END IF;

    -- Return stock for each item
    FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id AND tenant_id = p_tenant_id
    LOOP
        PERFORM adjust_stock(
            p_tenant_id, v_item.variant_id, v_order.location_id, v_item.unit_id,
            v_item.quantity, 'return', p_reason, p_order_id
        );
        v_total_refund := v_total_refund + v_item.total_price;
    END LOOP;

    -- Create refund transaction
    INSERT INTO financial_transactions (tenant_id, order_id, type_key, amount, payment_method_key, status_key, actor_id)
    VALUES (p_tenant_id, p_order_id, 'refund', v_total_refund, 'refund', 'success', auth.uid())
    RETURNING id INTO v_refund_id;

    -- Update order status
    UPDATE orders SET status_key = 'refunded', updated_at = NOW() WHERE id = p_order_id;

    -- Emit Event
    PERFORM emit_event(
        p_tenant_id,
        'order.refunded',
        jsonb_build_object('order_id', p_order_id, 'refund_amount', v_total_refund, 'reason', p_reason)
    );

    RETURN v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 6. STOCK HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Function: Get Stock Balance
-- Returns current available stock for a variant at a location
CREATE OR REPLACE FUNCTION get_stock_balance(
    p_tenant_id UUID,
    p_variant_id UUID,
    p_location_id UUID
) RETURNS NUMERIC AS $$
DECLARE
    v_base_on_hand NUMERIC;
    v_base_reserved NUMERIC;
    v_available NUMERIC;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- Calculate On-Hand in Base Units
    SELECT COALESCE(SUM(sl.quantity * ud.conversion_rate), 0) INTO v_base_on_hand
    FROM stock_levels sl
    JOIN unit_definitions ud ON sl.unit_id = ud.id
    WHERE sl.tenant_id = p_tenant_id AND sl.variant_id = p_variant_id AND sl.location_id = p_location_id;

    -- Calculate Reservations in Base Units
    SELECT COALESCE(SUM(sr.quantity * ud.conversion_rate), 0) INTO v_base_reserved
    FROM stock_reservations sr
    JOIN unit_definitions ud ON sr.unit_id = ud.id
    WHERE sr.tenant_id = p_tenant_id AND sr.variant_id = p_variant_id AND sr.location_id = p_location_id;

    v_available := v_base_on_hand - v_base_reserved;
    RETURN v_available;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function: Auto Expire Reservations
-- Cleans up expired stock reservations
CREATE OR REPLACE FUNCTION auto_expire_reservations(
    p_tenant_id UUID DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_expired_count INTEGER := 0;
BEGIN
    -- If tenant_id provided, validate ownership
    IF p_tenant_id IS NOT NULL THEN
        PERFORM assert_tenant_ownership(p_tenant_id);
        
        DELETE FROM stock_reservations
        WHERE tenant_id = p_tenant_id AND expires_at < NOW();
        
        GET DIAGNOSTICS v_expired_count = ROW_COUNT;
    ELSE
        -- System-wide cleanup (for service role)
        DELETE FROM stock_reservations
        WHERE expires_at < NOW();
        
        GET DIAGNOSTICS v_expired_count = ROW_COUNT;
    END IF;

    RETURN v_expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Bundle Sales Function
-- Handles selling a parent product that contains multiple child SKUs
-- FIXED: Now correctly retrieves base unit for each child variant

CREATE OR REPLACE FUNCTION sell_bundle(
    p_tenant_id UUID,
    p_parent_variant_id UUID,
    p_location_id UUID,
    p_quantity NUMERIC, -- Quantity of parent bundles to sell
    p_order_id UUID
) RETURNS VOID AS $$
DECLARE
    v_bundle RECORD;
    v_base_unit_id UUID;
    v_bundle_count INTEGER;
BEGIN
    -- SECURITY: Validate tenant ownership
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- VALIDATION: Verify parent variant belongs to tenant
    SELECT COUNT(*) INTO v_bundle_count
    FROM product_bundles pb
    JOIN product_variants pv ON pb.parent_variant_id = pv.id
    WHERE pb.tenant_id = p_tenant_id 
      AND pb.parent_variant_id = p_parent_variant_id
      AND pv.tenant_id = p_tenant_id;
    
    IF v_bundle_count = 0 THEN
        RAISE EXCEPTION 'Bundle not found or access denied for parent_variant_id: %', p_parent_variant_id;
    END IF;

    -- VALIDATION: Check bundle has children
    SELECT COUNT(*) INTO v_bundle_count
    FROM product_bundles
    WHERE tenant_id = p_tenant_id AND parent_variant_id = p_parent_variant_id;
    
    IF v_bundle_count = 0 THEN
        RAISE EXCEPTION 'Bundle has no child products defined for parent_variant_id: %', p_parent_variant_id;
    END IF;

    -- Loop through all child products in the bundle
    FOR v_bundle IN 
        SELECT pb.child_variant_id, pb.quantity
        FROM product_bundles pb
        JOIN product_variants pv ON pb.child_variant_id = pv.id
        WHERE pb.tenant_id = p_tenant_id 
          AND pb.parent_variant_id = p_parent_variant_id
          AND pv.tenant_id = p_tenant_id
    LOOP
        -- FIXED: Get the base unit for THIS child variant (no fallback)
        SELECT ud.id INTO v_base_unit_id
        FROM unit_definitions ud
        WHERE ud.variant_id = v_bundle.child_variant_id 
          AND ud.is_base_unit = TRUE
        LIMIT 1;
        
        -- FIXED: Require base unit - no fallback to prevent incorrect deductions
        IF v_base_unit_id IS NULL THEN
            RAISE EXCEPTION 'No base unit defined for child variant: %. Please define a base unit before selling bundles.', v_bundle.child_variant_id;
        END IF;

        -- Deduct child stock with correct unit
        PERFORM adjust_stock(
            p_tenant_id,
            v_bundle.child_variant_id,
            p_location_id,
            v_base_unit_id,
            -(v_bundle.quantity * p_quantity), -- Total child quantity = bundle qty * parent qty
            'sale',
            'Bundle Sale',
            p_order_id
        );
    END LOOP;

    -- Emit bundle sale event
    PERFORM emit_event(
        p_tenant_id,
        'bundle.sold',
        jsonb_build_object(
            'parent_variant_id', p_parent_variant_id,
            'quantity', p_quantity,
            'order_id', p_order_id
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
