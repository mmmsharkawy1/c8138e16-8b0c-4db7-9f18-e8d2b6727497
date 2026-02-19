# Enterprise-Grade Core Design Review

Technical review of Phases 1-4 for the Wholesale SaaS Platform.

---

## Phase 1: Domain Modeling

| Criterion | Status | Notes |
|-----------|--------|-------|
| Bounded Contexts Defined | ✅ | 6 contexts identified (Identity, Catalog, Inventory, Sales, Pricing, Events). |
| Core vs. Module Separation | ✅ | POS, Storefront, Tax Engines explicitly marked as non-Core. |
| Event-Driven Architecture | ✅ | Event Infrastructure domain handles decoupling. |
| Aggregate Boundaries | ⚠️ | `Customer` entity not defined. Recommended: Add to Tenancy or Sales. |

**Status: ✅ APPROVED** (with minor recommendation)

---

## Phase 2: Core Database Schema

| Criterion | Status | Notes |
|-----------|--------|-------|
| `tenant_id` on all tables | ✅ | Correctly applied to all business tables. |
| Multi-Unit Support | ✅ | `unit_definitions` with `conversion_rate` is extensible. |
| Inventory Auditability | ✅ | `stock_movements` tracks `balance_after`. |
| Soft Delete | ⚠️ | **Missing.** `is_active` is present but no `deleted_at` timestamp for recovery/audit. |
| Categories Table | ⚠️ | `category_id` FK referenced in `products` but `categories` table not defined. |
| Customer Table | ⚠️ | `customer_id` referenced in `orders` but table missing. |

> [!IMPORTANT]
> **Action Required:** Add `categories` and `customers` tables or remove dangling FKs.

**Status: ⚠️ CONDITIONALLY APPROVED** (requires minor additions)

---

## Phase 3: RLS & Access Control

| Criterion | Status | Notes |
|-----------|--------|-------|
| Tenant Isolation | ✅ | `auth.get_tenant_id()` enforced on all policies. |
| Granular Profile Access | ✅ | Owner/Manager/User access correctly separated. |
| Stock Write Protection | ✅ | `stock_levels` has no write policies (Service Role only). |
| Catalog RLS | ⚠️ | **Missing.** Comment `-- ... (Approved)` but no actual policies for `products`, `variants`, `units`. |
| Orders/Pricing/Financials RLS | ⚠️ | **Missing.** Policies for `orders`, `order_items`, `financial_transactions`, `pricing_rules` not defined. |
| Locations RLS | ⚠️ | `locations` has RLS enabled but no SELECT/WRITE policies. |

> [!WARNING]
> **Critical Gap:** Missing RLS policies for Catalog, Orders, Pricing, and Financials tables. Must be added before production.

**Status: ❌ NOT APPROVED** (critical gaps)

---

## Phase 4: Core Functions & Transaction Layer

| Criterion | Status | Notes |
|-----------|--------|-------|
| Atomicity | ✅ | Functions use single transaction scope. |
| Audit Logging | ✅ | `stock_movements` and `event_log` populated. |
| Event Emission | ✅ | `emit_event` called in all functions. |
| `tenant_id` Enforcement | ⚠️ | Functions accept `p_tenant_id` as parameter. Not validated against `auth.get_tenant_id()`. |
| `cancel_order` | ❌ | **Missing.** Function not implemented. |
| `release_stock` | ❌ | **Missing.** Function not implemented. |
| Stock Availability Check | ⚠️ | `create_order` deducts stock without pre-checking availability (could go negative). |
| `log_payment` Order Validation | ⚠️ | No check if `order_id` belongs to `tenant_id`. |

> [!CAUTION]
> **Security Risk:** Functions do not validate that `p_tenant_id` matches the authenticated user's tenant. A malicious caller could manipulate data for other tenants if the function is exposed.

> [!IMPORTANT]
> **Missing Functions:** `cancel_order`, `release_stock` are required for a complete transactional layer.

**Status: ⚠️ CONDITIONALLY APPROVED** (requires security fix + missing functions)

---

## Overall Summary

| Phase | Status | Priority Fixes |
|-------|--------|----------------|
| Phase 1: Domain Modeling | ✅ Approved | Add `Customer` entity definition. |
| Phase 2: Core Schema | ⚠️ Conditional | Add `categories`, `customers` tables. |
| Phase 3: RLS | ❌ Not Approved | Add missing policies for Catalog, Orders, Pricing, Financials, Locations. |
| Phase 4: Core Functions | ⚠️ Conditional | Add tenant validation, `cancel_order`, `release_stock`, stock availability check. |
