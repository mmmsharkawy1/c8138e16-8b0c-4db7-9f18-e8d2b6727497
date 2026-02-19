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
