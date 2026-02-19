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
