-- Phase 2: Core Database Schema Design
-- Target: PostgreSQL / Supabase
-- Strict Rules: tenant_id on every table, no module-specific logic.

-- 1. IDENTITY & TENANCY
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    subdomain TEXT UNIQUE,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- SAAS GOVERNANCE (Subscriptions, Plans, Limits)
--------------------------------------------------------------------------------

CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL, -- 'Free', 'Silver', 'Gold', 'Enterprise'
    price_monthly NUMERIC(10, 2),
    max_users INTEGER,
    max_locations INTEGER,
    max_products INTEGER,
    features JSONB DEFAULT '{}', -- {"advanced_reports": true, "api_access": true}
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE tenant_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    plan_id UUID REFERENCES subscription_plans(id) NOT NULL,
    status TEXT NOT NULL DEFAULT 'active', -- 'active', 'suspended', 'cancelled'
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ,
    auto_renew BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    feature_key TEXT NOT NULL, -- 'pos_offline', 'multi_currency', 'api_access'
    is_enabled BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, feature_key)
);

--------------------------------------------------------------------------------
-- NICHE TEMPLATES (Onboarding Wizard)
--------------------------------------------------------------------------------

CREATE TABLE niche_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    niche_type TEXT UNIQUE NOT NULL, -- 'clothing', 'auto_parts', 'fmcg'
    display_name TEXT NOT NULL,
    product_schema JSONB NOT NULL, -- {"color": "text", "size": "select", "material": "text"}
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE tenant_settings (
    tenant_id UUID PRIMARY KEY REFERENCES tenants(id),
    niche_type TEXT REFERENCES niche_templates(niche_type),
    onboarding_completed BOOLEAN DEFAULT FALSE,
    custom_fields JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- IDENTITY & ACCESS
--------------------------------------------------------------------------------

CREATE TABLE profiles (
    id UUID PRIMARY KEY, -- Maps to auth.users.id
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    full_name TEXT,
    role_key TEXT NOT NULL, -- e.g., 'owner', 'manager', 'cashier'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES categories(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    group_key TEXT, -- e.g., 'vip', 'wholesale', 'retail'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

--------------------------------------------------------------------------------
-- 2. CATALOG (ABSTRACT DEFINITIONS)
--------------------------------------------------------------------------------

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    type_key TEXT NOT NULL, -- e.g., 'clothing', 'food'
    category_id UUID REFERENCES categories(id),
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
    sku TEXT NOT NULL,
    barcode TEXT,
    attributes JSONB DEFAULT '{}', -- e.g., {"size": "XL", "color": "Red"}
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
    -- NOTE: Unique constraint on (tenant_id, sku) is handled via partial index below
    -- to properly support soft delete functionality
);

CREATE TABLE unit_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    variant_id UUID REFERENCES product_variants(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL, -- e.g., 'Piece', 'Carton'
    conversion_rate NUMERIC(15, 4) NOT NULL DEFAULT 1, -- Base unit = 1
    is_base_unit BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PRODUCT BUNDLES (Dynamic Parent-Child)
CREATE TABLE product_bundles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    parent_variant_id UUID REFERENCES product_variants(id) ON DELETE CASCADE NOT NULL,
    child_variant_id UUID REFERENCES product_variants(id) ON DELETE CASCADE NOT NULL,
    quantity NUMERIC(15, 4) NOT NULL, -- How many units of child in parent
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, parent_variant_id, child_variant_id)
);

-- 3. INVENTORY (PHYSICAL STOCK)
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    name TEXT NOT NULL,
    type_key TEXT NOT NULL, -- 'warehouse', 'branch', 'van'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE TABLE stock_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    variant_id UUID REFERENCES product_variants(id) NOT NULL,
    location_id UUID REFERENCES locations(id) NOT NULL,
    unit_id UUID REFERENCES unit_definitions(id) NOT NULL,
    quantity NUMERIC(15, 4) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, variant_id, location_id, unit_id)
);

CREATE TABLE stock_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    variant_id UUID REFERENCES product_variants(id) NOT NULL,
    location_id UUID REFERENCES locations(id) NOT NULL,
    unit_id UUID REFERENCES unit_definitions(id) NOT NULL,
    change_quantity NUMERIC(15, 4) NOT NULL,
    balance_after NUMERIC(15, 4) NOT NULL,
    type_key TEXT NOT NULL, -- 'sale', 'adjustment', 'transfer', 'return'
    reason TEXT,
    reference_id UUID, -- Link to Order, etc.
    actor_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE stock_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    variant_id UUID REFERENCES product_variants(id) NOT NULL,
    location_id UUID REFERENCES locations(id) NOT NULL,
    unit_id UUID REFERENCES unit_definitions(id) NOT NULL,
    order_id UUID,
    quantity NUMERIC(15, 4) NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. SALES (ORDER LIFECYCLE)
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    customer_id UUID REFERENCES customers(id),
    location_id UUID REFERENCES locations(id) NOT NULL,
    status_key TEXT NOT NULL, -- 'draft', 'pending', 'completed', 'cancelled'
    total_amount NUMERIC(15, 4) DEFAULT 0,
    tax_amount NUMERIC(15, 4) DEFAULT 0,
    discount_amount NUMERIC(15, 4) DEFAULT 0,
    net_amount NUMERIC(15, 4) DEFAULT 0,
    currency_code TEXT DEFAULT 'USD',
    actor_id UUID REFERENCES profiles(id),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    variant_id UUID REFERENCES product_variants(id) NOT NULL,
    unit_id UUID REFERENCES unit_definitions(id) NOT NULL,
    quantity NUMERIC(15, 4) NOT NULL,
    unit_price NUMERIC(15, 4) NOT NULL,
    total_price NUMERIC(15, 4) NOT NULL,
    tax_rate NUMERIC(5, 4) DEFAULT 0, -- e.g., 0.1400
    tax_amount NUMERIC(15, 4) DEFAULT 0,
    discount_amount NUMERIC(15, 4) DEFAULT 0,
    net_amount NUMERIC(15, 4) DEFAULT 0, -- Price before tax (unit_price * quantity)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE financial_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    order_id UUID REFERENCES orders(id),
    type_key TEXT NOT NULL, -- 'payment', 'refund'
    amount NUMERIC(15, 4) NOT NULL,
    payment_method_key TEXT, -- 'cash', 'card', 'bank_transfer'
    status_key TEXT NOT NULL, -- 'pending', 'success', 'failed'
    actor_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. PRICING RULES
CREATE TABLE pricing_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    variant_id UUID REFERENCES product_variants(id),
    unit_id UUID REFERENCES unit_definitions(id),
    customer_group_id UUID,
    min_quantity NUMERIC(15, 4) DEFAULT 1,
    price NUMERIC(15, 4) NOT NULL,
    priority INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    valid_from TIMESTAMPTZ,
    valid_to TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. EVENT LOG (IMMUTABLE LEDGER)
CREATE TABLE event_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) NOT NULL,
    event_type TEXT NOT NULL, -- 'order.created', 'stock.adjusted'
    payload JSONB NOT NULL,
    actor_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDEXES FOR MULTI-TENANCY PERFORMANCE
CREATE INDEX idx_profiles_tenant ON profiles(tenant_id);
CREATE INDEX idx_products_tenant ON products(tenant_id);
CREATE INDEX idx_variants_tenant ON product_variants(tenant_id);
CREATE INDEX idx_stock_tenant ON stock_levels(tenant_id);
CREATE INDEX idx_orders_tenant ON orders(tenant_id);
CREATE INDEX idx_events_tenant ON event_log(tenant_id);

-- ADDITIONAL PERFORMANCE INDEXES
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_variants_product ON product_variants(product_id);

-- PERFORMANCE INDEXES FOR FREQUENTLY QUERIED COLUMNS
-- Stock levels by variant and location (for stock checks)
CREATE INDEX idx_stock_levels_variant_loc ON stock_levels(variant_id, location_id);

-- (Removed: Partial index with NOW() - not IMMUTABLE)

-- Orders by status for filtering
CREATE INDEX idx_orders_status ON orders(tenant_id, status_key);

-- Event log by type and date for auditing
CREATE INDEX idx_event_log_type_date ON event_log(tenant_id, event_type, created_at);

-- Unit definitions by variant for stock calculations
CREATE INDEX idx_unit_definitions_variant ON unit_definitions(variant_id);

-- Stock movements for audit trails
CREATE INDEX idx_stock_movements_variant ON stock_movements(tenant_id, variant_id, created_at DESC);

-- Product bundles by parent for bundle sales
CREATE INDEX idx_product_bundles_parent ON product_bundles(parent_variant_id);

--------------------------------------------------------------------------------
-- GIN INDEXES FOR JSONB PERFORMANCE
--------------------------------------------------------------------------------

-- GIN index for products.metadata (niche-specific attributes)
CREATE INDEX IF NOT EXISTS idx_products_metadata ON products USING GIN(metadata);

-- GIN index for product_variants.attributes (size, color, etc.)
CREATE INDEX IF NOT EXISTS idx_variants_attributes ON product_variants USING GIN(attributes);

-- GIN index for customers.metadata
CREATE INDEX IF NOT EXISTS idx_customers_metadata ON customers USING GIN(metadata);

-- GIN index for locations.metadata
CREATE INDEX IF NOT EXISTS idx_locations_metadata ON locations USING GIN(metadata);

-- GIN index for orders.metadata
CREATE INDEX IF NOT EXISTS idx_orders_metadata ON orders USING GIN(metadata);

-- GIN index for tenant settings
CREATE INDEX IF NOT EXISTS idx_tenant_settings_niche ON tenant_settings(niche_type);

-- GIN index for event log payload (for querying event data)
CREATE INDEX IF NOT EXISTS idx_event_log_payload ON event_log USING GIN(payload);

--------------------------------------------------------------------------------
-- DATA INTEGRITY CONSTRAINTS
--------------------------------------------------------------------------------

-- CRITICAL: Unique SKU per tenant (excluding soft-deleted records)
-- This partial index ensures:
-- 1. Active SKUs are unique per tenant
-- 2. Soft-deleted variants can have duplicate SKUs (allows reusing SKU after deletion)
-- 3. When a deleted variant is restored, uniqueness is enforced again
-- NOTE: The table-level UNIQUE constraint was removed to support this soft-delete pattern
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_sku_active 
    ON product_variants(tenant_id, sku) 
    WHERE deleted_at IS NULL;

-- Unique email per tenant for customers (excluding soft-deleted records)
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_email_active 
    ON customers(tenant_id, email) 
    WHERE deleted_at IS NULL AND email IS NOT NULL;

--------------------------------------------------------------------------------
-- RACE CONDITION PREVENTION INDEXES
--------------------------------------------------------------------------------

-- Index for stock_reservations to support efficient locking in reserve_stock()
CREATE INDEX IF NOT EXISTS idx_stock_reservations_variant_loc 
    ON stock_reservations(tenant_id, variant_id, location_id);

-- Index for stock_levels to support efficient locking in reserve_stock()
CREATE INDEX IF NOT EXISTS idx_stock_levels_tenant_variant_loc 
    ON stock_levels(tenant_id, variant_id, location_id);

--------------------------------------------------------------------------------
-- ADVISORY LOCK HELPER FUNCTION
--------------------------------------------------------------------------------

-- Helper function to generate consistent lock keys for variant+location combinations
-- Used by reserve_stock() to prevent race conditions
CREATE OR REPLACE FUNCTION get_stock_lock_key(
    p_variant_id UUID,
    p_location_id UUID
) RETURNS BIGINT AS $$
BEGIN
    -- Generate a deterministic 64-bit key from variant_id and location_id
    -- Using SHA-256 and taking first 64 bits for the advisory lock
    RETURN ('x' || encode(sha256(p_variant_id::text || p_location_id::text), 'hex'))::bit(64)::bigint;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
-- Seed Data for Niche Templates
-- Run this after core_schema.sql to populate the onboarding wizard options

INSERT INTO niche_templates (niche_type, display_name, product_schema) VALUES
(
    'clothing',
    'Clothing & Fashion',
    '{
        "color": {"type": "text", "label": "Color", "required": false},
        "size": {"type": "select", "label": "Size", "options": ["XS", "S", "M", "L", "XL", "XXL"], "required": false},
        "material": {"type": "text", "label": "Material", "required": false}
    }'::JSONB
),
(
    'auto_parts',
    'Auto Parts & Accessories',
    '{
        "part_number": {"type": "text", "label": "Part Number", "required": true},
        "car_model": {"type": "text", "label": "Car Model", "required": false},
        "engine_type": {"type": "text", "label": "Engine Type", "required": false}
    }'::JSONB
),
(
    'fmcg',
    'FMCG & Food Products',
    '{
        "expiry_date": {"type": "date", "label": "Expiry Date", "required": false},
        "batch_number": {"type": "text", "label": "Batch Number", "required": false},
        "brand": {"type": "text", "label": "Brand", "required": false}
    }'::JSONB
);
-- SaaS Governance Helper Functions
-- These functions are used to enforce subscription limits and feature access

--------------------------------------------------------------------------------
-- 1. GET TENANT LIMITS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_tenant_limit(
    p_tenant_id UUID,
    p_limit_key TEXT -- 'max_users', 'max_locations', 'max_products'
) RETURNS INTEGER AS $$
DECLARE
    v_limit INTEGER;
BEGIN
    SELECT 
        CASE p_limit_key
            WHEN 'max_users' THEN sp.max_users
            WHEN 'max_locations' THEN sp.max_locations
            WHEN 'max_products' THEN sp.max_products
            ELSE NULL
        END INTO v_limit
    FROM tenant_subscriptions ts
    JOIN subscription_plans sp ON ts.plan_id = sp.id
    WHERE ts.tenant_id = p_tenant_id 
    AND ts.status = 'active'
    AND (ts.ends_at IS NULL OR ts.ends_at > NOW())
    ORDER BY ts.created_at DESC
    LIMIT 1;

    RETURN COALESCE(v_limit, 0);
END;
$$ LANGUAGE plpgsql STABLE;

--------------------------------------------------------------------------------
-- 2. CHECK FEATURE ACCESS
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION has_feature_access(
    p_tenant_id UUID,
    p_feature_key TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_enabled BOOLEAN;
    v_plan_features JSONB;
BEGIN
    -- Check explicit feature flag first
    SELECT is_enabled INTO v_enabled
    FROM feature_flags
    WHERE tenant_id = p_tenant_id AND feature_key = p_feature_key;

    IF v_enabled IS NOT NULL THEN
        RETURN v_enabled;
    END IF;

    -- Fallback to plan features
    SELECT sp.features INTO v_plan_features
    FROM tenant_subscriptions ts
    JOIN subscription_plans sp ON ts.plan_id = sp.id
    WHERE ts.tenant_id = p_tenant_id 
    AND ts.status = 'active'
    AND (ts.ends_at IS NULL OR ts.ends_at > NOW())
    ORDER BY ts.created_at DESC
    LIMIT 1;

    RETURN COALESCE((v_plan_features ->> p_feature_key)::BOOLEAN, FALSE);
END;
$$ LANGUAGE plpgsql STABLE;

--------------------------------------------------------------------------------
-- 3. VALIDATE TENANT LIMIT (Throws exception if exceeded)
-- FIXED: Added whitelist validation to prevent SQL Injection
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION validate_tenant_limit(
    p_tenant_id UUID,
    p_table_name TEXT
) RETURNS VOID AS $$
DECLARE
    v_limit INTEGER;
    v_current_count INTEGER;
    v_limit_key TEXT;
    -- Whitelist of allowed table names for security
    v_allowed_tables TEXT[] := ARRAY['profiles', 'locations', 'products'];
BEGIN
    -- SECURITY: Validate tenant ownership first
    PERFORM assert_tenant_ownership(p_tenant_id);

    -- SECURITY: Whitelist validation to prevent SQL Injection
    IF p_table_name IS NULL OR NOT (p_table_name = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'Invalid table name: %. Allowed tables: %', 
            p_table_name, array_to_string(v_allowed_tables, ', ')
            USING ERRCODE = '42501';
    END IF;

    -- Map table name to limit key
    v_limit_key := CASE p_table_name
        WHEN 'profiles' THEN 'max_users'
        WHEN 'locations' THEN 'max_locations'
        WHEN 'products' THEN 'max_products'
        ELSE NULL
    END;

    IF v_limit_key IS NULL THEN
        RETURN; -- No limit for this table
    END IF;

    v_limit := get_tenant_limit(p_tenant_id, v_limit_key);

    -- SECURITY: Using format with %I is now safe after whitelist validation
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE tenant_id = $1 AND deleted_at IS NULL', p_table_name)
    INTO v_current_count
    USING p_tenant_id;

    IF v_current_count >= v_limit THEN
        RAISE EXCEPTION 'Subscription limit exceeded: % (limit: %, current: %)', 
            v_limit_key, v_limit, v_current_count
            USING ERRCODE = '42501';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Phase 3: Row Level Security (RLS) & Access Control
-- Target: Supabase / PostgreSQL
-- Rules: All tables must enable RLS. All access must be filtered by tenant_id.

-- HELPER FUNCTION: Get Tenant ID from JWT
-- In Supabase, we can store tenant_id in JWT metadata or use a lookup.
-- For maximum security, we'll assume it's in the JWT app_metadata.
CREATE OR REPLACE FUNCTION auth.get_tenant_id()
RETURNS UUID AS $$
    SELECT (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::UUID;
$$ LANGUAGE SQL STABLE;

-- HELPER FUNCTION: Get Current Profile Role
-- OPTIMIZED: Reads from JWT first (fast), falls back to DB if not cached.
CREATE OR REPLACE FUNCTION auth.get_role()
RETURNS TEXT AS $$
    SELECT COALESCE(
        (auth.jwt() -> 'app_metadata' ->> 'role_key'),
        (SELECT role_key FROM public.profiles WHERE id = auth.uid())
    );
$$ LANGUAGE SQL STABLE;

--------------------------------------------------------------------------------
-- 1. TENANTS
--------------------------------------------------------------------------------
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

-- Residents can see their own tenant details.
CREATE POLICY "Tenants are visible to their members"
ON tenants FOR SELECT
USING (id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 2. PROFILES (GRANULAR ACCESS)
--------------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- SELECT: Everyone in tenant can see other members.
CREATE POLICY "Profiles visible within tenant" ON profiles FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- UPDATE: User can update their own metadata (not role).
CREATE POLICY "Users can update own info (excluded role)" ON profiles FOR UPDATE
USING (id = auth.uid())
WITH CHECK (
  id = auth.uid() AND 
  (CASE WHEN role_key IS DISTINCT FROM (SELECT role_key FROM profiles WHERE id = auth.uid()) THEN FALSE ELSE TRUE END)
);

-- UPDATE: Manager can update metadata/name of others (not role).
CREATE POLICY "Managers can update profile details (not roles)" ON profiles FOR UPDATE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'manager')
WITH CHECK (
  tenant_id = auth.get_tenant_id() AND 
  (CASE WHEN role_key IS DISTINCT FROM (SELECT role_key FROM profiles WHERE id = profiles.id) THEN FALSE ELSE TRUE END)
);

-- UPDATE: Owner has full control including role_key.
CREATE POLICY "Owners have full profile control" ON profiles FOR UPDATE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner')
WITH CHECK (tenant_id = auth.get_tenant_id());

-- INSERT/DELETE: Restricted to Owner (with subscription limit check).
CREATE POLICY "Owners can create/delete profiles" ON profiles FOR INSERT
WITH CHECK (
    tenant_id = auth.get_tenant_id() AND 
    auth.get_role() = 'owner' AND
    (SELECT validate_tenant_limit(auth.get_tenant_id(), 'profiles')) IS NULL
);

CREATE POLICY "Owners can delete profiles" ON profiles FOR DELETE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner');

--------------------------------------------------------------------------------
-- 3. CATALOG (Products, Variants, Units, Categories)
--------------------------------------------------------------------------------
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE unit_definitions ENABLE ROW LEVEL SECURITY;

-- SELECT: All authenticated users in the tenant can view catalog.
CREATE POLICY "Categories visible to tenant members" ON categories FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Products visible to tenant members" ON products FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Variants visible to tenant members" ON product_variants FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Units visible to tenant members" ON unit_definitions FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- WRITE: Only Owner and Manager can modify catalog.
CREATE POLICY "Categories manageable by management" ON categories FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());

CREATE POLICY "Products manageable by management" ON products FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (
    tenant_id = auth.get_tenant_id() AND
    (TG_OP = 'UPDATE' OR (SELECT validate_tenant_limit(auth.get_tenant_id(), 'products')) IS NULL)
);

CREATE POLICY "Variants manageable by management" ON product_variants FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());

CREATE POLICY "Units manageable by management" ON unit_definitions FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 3.5 CUSTOMERS (CRM)
--------------------------------------------------------------------------------
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Customers visible to tenant members" ON customers FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Customers manageable by staff" ON customers FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager', 'cashier'))
WITH CHECK (tenant_id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 3.6 LOCATIONS
--------------------------------------------------------------------------------
-- SELECT: All staff can view locations.
CREATE POLICY "Locations visible to tenant members" ON locations FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- WRITE: Only Owner and Manager (with subscription limit check on INSERT).
CREATE POLICY "Locations manageable by management" ON locations FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (
    tenant_id = auth.get_tenant_id() AND
    (TG_OP = 'UPDATE' OR (SELECT validate_tenant_limit(auth.get_tenant_id(), 'locations')) IS NULL)
);

--------------------------------------------------------------------------------
-- 4. INVENTORY & STOCK (STRICT SERVICE LAYER)
--------------------------------------------------------------------------------
ALTER TABLE stock_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;

-- SELECT: Staff can see stock.
CREATE POLICY "Stock info visible to tenant members" ON stock_levels FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- CRITICAL: No direct UPDATE/INSERT/DELETE allowed on stock_levels.
-- Writable ONLY via PostgreSQL Functions (to be defined in Phase 4).
-- No policies here = Access Denied to all but Service Role.

-- Movements: Staff can log stock changes.
CREATE POLICY "Staff can view movements" ON stock_movements FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Authorized staff can log movements" ON stock_movements FOR INSERT
WITH CHECK (
    tenant_id = auth.get_tenant_id() AND 
    auth.get_role() IN ('owner', 'manager', 'cashier')
);

--------------------------------------------------------------------------------
-- 5. STOCK RESERVATIONS
--------------------------------------------------------------------------------
ALTER TABLE stock_reservations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Staff can view reservations" ON stock_reservations FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Staff can create reservations" ON stock_reservations FOR INSERT
WITH CHECK (
    tenant_id = auth.get_tenant_id() AND 
    auth.get_role() IN ('owner', 'manager', 'cashier')
);

CREATE POLICY "Owner and Manager can remove reservations" ON stock_reservations FOR DELETE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'));

-- NOTE: System-level cleanup of expired reservations assumes service role bypass or specialized function.

--------------------------------------------------------------------------------
-- 6. SALES (Orders, Order Items)
--------------------------------------------------------------------------------
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- SELECT: All staff can view orders.
CREATE POLICY "Orders visible to tenant members" ON orders FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Order items visible to tenant members" ON order_items FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- CRITICAL: INSERT/UPDATE/DELETE for orders MUST go through core functions.
-- Direct writes are restricted to authorized roles for emergency fixes only.
CREATE POLICY "Orders creatable by staff" ON orders FOR INSERT
WITH CHECK (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager', 'cashier'));

CREATE POLICY "Orders manageable by management" ON orders FOR UPDATE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());

CREATE POLICY "Order items insertable by staff" ON order_items FOR INSERT
WITH CHECK (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager', 'cashier'));

CREATE POLICY "Management can delete order items" ON order_items FOR DELETE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'));

CREATE POLICY "Owners can delete orders" ON orders FOR DELETE
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner');

--------------------------------------------------------------------------------
-- 7. FINANCIAL TRANSACTIONS
--------------------------------------------------------------------------------
ALTER TABLE financial_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Transactions visible to tenant members" ON financial_transactions FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- WRITE: Restricted to Owner, Manager, Cashier (ideally via functions).
CREATE POLICY "Transactions creatable by staff" ON financial_transactions FOR INSERT
WITH CHECK (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager', 'cashier'));

-- No UPDATE/DELETE policies = immutable after creation.

--------------------------------------------------------------------------------
-- 8. PRICING RULES
--------------------------------------------------------------------------------
ALTER TABLE pricing_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Pricing rules visible to staff" ON pricing_rules FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Pricing rules manageable by management" ON pricing_rules FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 9. EVENT LOG (IMMUTABLE PROTECTION)
--------------------------------------------------------------------------------
ALTER TABLE event_log ENABLE ROW LEVEL SECURITY;

-- SELECT: Everyone in tenant can see logs (for auditing/UI purposes).
CREATE POLICY "Event logs visible to tenant members" ON event_log FOR SELECT
USING (tenant_id = auth.get_tenant_id());

-- Event Log Protection:
-- Writable primarily via DB triggers or security-definer functions for audit integrity.
-- Direct INSERT policy if needed for specific apps:
CREATE POLICY "Staff can log events" ON event_log FOR INSERT
WITH CHECK (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager', 'cashier'));

-- No UPDATE/DELETE policies = Access Denied.

--------------------------------------------------------------------------------
-- 10. SAAS GOVERNANCE TABLES
--------------------------------------------------------------------------------

-- Subscription Plans (Global - Read Only for Tenants)
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Subscription plans visible to all authenticated users" ON subscription_plans FOR SELECT
USING (is_active = TRUE);

-- Tenant Subscriptions
ALTER TABLE tenant_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant subscriptions visible to tenant members" ON tenant_subscriptions FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Owners can manage subscriptions" ON tenant_subscriptions FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner')
WITH CHECK (tenant_id = auth.get_tenant_id());

-- Feature Flags
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Feature flags visible to tenant members" ON feature_flags FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Owners can manage feature flags" ON feature_flags FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner')
WITH CHECK (tenant_id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 11. NICHE TEMPLATES (Onboarding)
--------------------------------------------------------------------------------

-- Niche Templates (Global - Read Only for Tenants)
ALTER TABLE niche_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Niche templates visible to all authenticated users" ON niche_templates FOR SELECT
USING (is_active = TRUE);

-- Tenant Settings
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant settings visible to tenant members" ON tenant_settings FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Owners can manage tenant settings" ON tenant_settings FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() = 'owner')
WITH CHECK (tenant_id = auth.get_tenant_id());

--------------------------------------------------------------------------------
-- 12. PRODUCT BUNDLES
--------------------------------------------------------------------------------

ALTER TABLE product_bundles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Product bundles visible to tenant members" ON product_bundles FOR SELECT
USING (tenant_id = auth.get_tenant_id());

CREATE POLICY "Product bundles manageable by management" ON product_bundles FOR ALL
USING (tenant_id = auth.get_tenant_id() AND auth.get_role() IN ('owner', 'manager'))
WITH CHECK (tenant_id = auth.get_tenant_id());
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
-- Seed Subscription Plans
-- Run after core_schema.sql to populate pricing tiers

INSERT INTO subscription_plans (name, price_monthly, max_users, max_locations, max_products, features, is_active) VALUES
(
    'Free',
    0,
    3,      -- max users
    1,      -- max locations
    100,    -- max products
    '{"api_access": false, "advanced_reports": false, "pos_offline": true}'::JSONB,
    TRUE
),
(
    'Silver',
    499,
    10,     -- max users
    3,      -- max locations
    500,    -- max products
    '{"api_access": false, "advanced_reports": true, "pos_offline": true}'::JSONB,
    TRUE
),
(
    'Gold',
    999,
    25,     -- max users
    10,     -- max locations
    2000,   -- max products
    '{"api_access": true, "advanced_reports": true, "pos_offline": true, "multi_currency": true}'::JSONB,
    TRUE
),
(
    'Enterprise',
    2499,
    NULL,   -- unlimited users
    NULL,   -- unlimited locations
    NULL,   -- unlimited products
    '{"api_access": true, "advanced_reports": true, "pos_offline": true, "multi_currency": true, "white_label": true, "priority_support": true}'::JSONB,
    TRUE
);
