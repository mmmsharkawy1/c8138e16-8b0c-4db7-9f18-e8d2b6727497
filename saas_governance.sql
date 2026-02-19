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
