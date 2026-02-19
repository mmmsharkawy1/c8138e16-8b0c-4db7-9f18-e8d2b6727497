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
