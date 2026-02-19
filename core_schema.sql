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

-- Expired reservations cleanup (partial index)
CREATE INDEX idx_stock_reservations_expires ON stock_reservations(expires_at) 
WHERE expires_at < NOW();

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
