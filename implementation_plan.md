# Implementation Plan: Enterprise-Grade Modular Wholesale Platform

Building a production-ready, modular commerce platform for long-term scaling (10+ years). Strict adherence to clean architecture and decoupled logic.

## 1. Non-Negotiable Engineering Rules
- **Core ≠ Modules**: Core is stable and independent; Modules (POS, Storefront) are pluggable.
- **Event-Driven**: All business actions emit persisted, replayable events.
- **Auditability**: Every inventory/financial change is logged as a transaction.
- **Strict RLS**: Supabase RLS enforced on every table with `tenant_id`.

## 2. Technical Architecture (Strict Monorepo)

### Directory Structure
- `apps/dashboard`: Merchant Management (Next.js 14).
- `apps/pos`: Electron POS Application.
- `packages/database`: Supabase Client, DB Types.
- `packages/shared`: Zod Schemas, TypeScript Types, Constants.
- `packages/ui`: (Planned) Shadcn/Tailwind Components.

## 3. Core Engine (Immutable)

### Event Sourcing & Audit Log [NEW]
- **Event Log Table**: `id, tenant_id, event_type, payload (JSONB), created_at`.
- **Inventory Transactions**: Every stock change creates a record in `inventory_transactions`.

### Product & Pricing Engine [NEW]
- **Abstract Products**: Support any industry via JSONB metadata.
- **Dynamic Pricing Rules**: A rules-engine approach (`customer_group`, `qty_tier`, `unit_id`) rather than static columns.
- **Conversion Chains**: User-defined units (e.g., Piece -> Dozen -> Carton).

## 4. Database Schema (Enterprise Refinement)

### Event & Audit System
```sql
event_log (
  id uuid primary key,
  tenant_id uuid references tenants,
  event_type text, -- order.created, inventory.adjusted
  payload jsonb,
  actor_id uuid references profiles,
  created_at timestamptz
);

inventory_transactions (
  id uuid primary key,
  tenant_id uuid references tenants,
  variant_id uuid references product_variants,
  location_id uuid references locations,
  type text, -- sale, adjustment, transfer, return
  quantity numeric,
  balance_after numeric,
  reference_id uuid, -- e.g., order_id
  created_at timestamptz
);
```

### Flexible Pricing Engine
```sql
pricing_rules (
  id uuid primary key,
  tenant_id uuid references tenants,
  variant_id uuid references product_variants,
  unit_id uuid references unit_definitions,
  customer_group text,
  min_quantity numeric default 1,
  price numeric,
  priority integer,
  active boolean
);
```

## Phase 4: Core Database Functions & Transaction Layer [NEW]

Establishing the "Service Layer" within the database to ensure atomicity, auditability, and multi-unit support.

### 1. Inventory Service Layer
- `adjust_stock(tenant_id, variant_id, location_id, unit_id, quantity, type, reason)`: Handles quantity changes, logs movement, and emits `stock.adjusted` event.
- `reserve_stock(...)` & `release_stock(...)`: Manages `stock_reservations` and emits corresponding events.
- **Unit Logic**: Ensures quantities are correctly converted to the base unit or specific unit context.

### 2. Sales & Transaction Layer
- `create_order(tenant_id, location_id, customer_id, items_jsonb)`: Validates stock, creates order + items, reserves/deducts stock, and emits `order.created`.
- `cancel_order(order_id)`: Reverses stock changes or releases reservations + emits `order.cancelled`.
- `log_financial_transaction(...)`: Records payments/refunds and emits `payment.completed`.

### 3. Automated Event Sourcing
- Every core function MUST insert into the `event_log` table as part of the same transaction.
- Triggers can be used for secondary audit logging if necessary, but primary events are emitted by the service functions.

## 6. Verification (No-Compromise)
- **Security**: Unit tests for RLS policies (Tenant leak checks).
- **Integrity**: Transactional integrity tests for inventory.
- **Resilience**: Offline POS sync simulation & conflict resolution.
- **Audit**: Event replay verification.
