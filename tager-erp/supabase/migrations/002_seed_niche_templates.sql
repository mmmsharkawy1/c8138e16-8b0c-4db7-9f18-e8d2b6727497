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
