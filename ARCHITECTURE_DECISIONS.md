# Architecture Decision Records (ADR)

## Overview
This document tracks all major architectural decisions made during TAGER ERP development.

---

## ADR-001: Authentication Provider Selection

**Date:** 2026-02-09  
**Status:** ✅ Approved  
**Context:** Need to choose between Clerk and Supabase Auth for user authentication.

### Decision
Use **Supabase Auth** with MFA enabled.

### Rationale
- Already using Supabase as primary database
- RLS policies are tightly integrated with Supabase Auth JWT
- Multi-tenant isolation via `tenant_id` in JWT claims works seamlessly
- MFA can be enabled in Supabase Auth settings
- Reduces external dependencies and costs

### Consequences
- No need for Clerk integration
- Simpler auth flow
- Existing RLS architecture remains unchanged
- MFA configuration required in Supabase Dashboard

---

## ADR-002: Niche Template System

**Date:** 2026-02-09  
**Status:** ✅ Implemented  
**Context:** Need flexible product schema for different business types (Clothing, Auto Parts, FMCG).

### Decision
Implement **Dynamic Niche Templates** using JSONB schemas.

### Rationale
- Each business type has unique product attributes
- JSONB allows schema flexibility without migrations
- Onboarding wizard can auto-configure based on selected niche
- Reduces setup time from hours to minutes

### Implementation
```sql
CREATE TABLE niche_templates (
    niche_type TEXT UNIQUE NOT NULL,
    product_schema JSONB NOT NULL
);

CREATE TABLE tenant_settings (
    tenant_id UUID PRIMARY KEY,
    niche_type TEXT REFERENCES niche_templates(niche_type),
    onboarding_completed BOOLEAN DEFAULT FALSE
);
```

### Supported Niches
1. **Clothing:** color, size, material
2. **Auto Parts:** part_number, car_model, engine_type
3. **FMCG:** expiry_date, batch_number, brand

---

## ADR-003: Dynamic Product Bundles

**Date:** 2026-02-09  
**Status:** ✅ Implemented  
**Context:** Wholesale businesses sell products in bundles (e.g., Dozen = 12 pieces, Mixed Sets).

### Decision
Implement **Dynamic Parent-Child Product Relationships**.

### Rationale
- Bundles are not fixed (e.g., "Mixed Sizes Set" = 2L + 4M + 6S)
- Need automatic stock deduction when bundle is sold
- Must maintain audit trail for compliance

### Implementation
```sql
CREATE TABLE product_bundles (
    parent_variant_id UUID,
    child_variant_id UUID,
    quantity NUMERIC(15, 4) NOT NULL
);

-- Function: sell_bundle()
-- Automatically deducts child SKUs when parent is sold
```

### Consequences
- Accurate inventory tracking for complex products
- Supports wholesale business logic
- Requires careful testing for edge cases

---

## ADR-004: Offline-First Architecture

**Date:** 2026-02-07  
**Status:** 📋 Planned (Phase 5)  
**Context:** Egyptian merchants face frequent internet outages.

### Decision
Use **PowerSync** for client-server replication with local SQLite cache.

### Rationale
- POS must work 100% offline
- PowerSync provides proven sync engine
- Last-Write-Wins conflict resolution
- Automatic retry on reconnection

### Architecture
```
Supabase (PostgreSQL)
  ↕ PowerSync Service
  ↕ Client (SQLite + React Query)
```

### Consequences
- Zero downtime for POS operations
- Requires PowerSync instance provisioning
- Sync rules must be carefully designed
- Conflict resolution strategy must be tested

---

## ADR-005: Electron Wrapper for POS

**Date:** 2026-02-07  
**Status:** 📋 Planned (Phase 5)  
**Context:** Need hardware integration (thermal printers, barcode scanners, cash drawers).

### Decision
Wrap **Next.js PWA in Electron** for POS application.

### Rationale
- Browser security restrictions prevent USB/Serial access
- Electron provides native API access
- Can reuse Next.js web codebase
- ESC/POS printer support via Node.js libraries

### Implementation
- Main Process: Hardware communication (IPC handlers)
- Renderer Process: Next.js UI
- Auto-update system for deployments

---

## ADR-006: SaaS Governance Model

**Date:** 2026-02-07  
**Status:** ✅ Implemented  
**Context:** Need subscription tiers (Free, Silver, Gold, Enterprise) with enforced limits.

### Decision
Implement **Database-Level Limit Enforcement** via RLS policies.

### Rationale
- Security at database layer (cannot be bypassed)
- Subscription limits enforced before INSERT operations
- Feature flags for granular control
- Supports monetization strategy

### Implementation
```sql
-- Tables: subscription_plans, tenant_subscriptions, feature_flags
-- Functions: get_tenant_limit(), has_feature_access(), validate_tenant_limit()
-- RLS: Policies check limits before allowing INSERT
```

### Consequences
- Prevents subscription abuse
- Clear upgrade path for tenants
- Requires careful UX for limit notifications

---

## ADR-007: Immutable Financial Ledger

**Date:** 2026-02-05  
**Status:** ✅ Implemented  
**Context:** Need fraud prevention and audit compliance.

### Decision
Block **DELETE and UPDATE** operations on financial transactions at database level.

### Rationale
- Prevents staff from deleting invoices after stealing cash
- Audit trail for tax compliance
- Corrections via reversal entries (standard accounting practice)

### Implementation
```sql
-- RLS Policies: No DELETE/UPDATE on invoices, payments
-- Corrections: INSERT reversal entry with negative amount
```

---

## ADR-008: ETA E-Invoicing Integration

**Date:** 2026-02-09  
**Status:** 🔜 Deferred to Phase 3  
**Context:** Egyptian Tax Authority requires e-invoicing.

### Decision
**Defer ETA integration** to Phase 3 expansion.

### Rationale
- Not critical for MVP launch
- Schema can be added later without breaking changes
- Focus on core POS and inventory first
- ETA API integration requires government approval process

### Future Implementation
- Add `tax_invoices` table
- ETA API client
- Digital signature support

---

## Summary Table

| ADR | Decision | Status | Impact |
|-----|----------|--------|--------|
| 001 | Supabase Auth + MFA | ✅ Approved | High |
| 002 | Niche Templates | ✅ Implemented | High |
| 003 | Dynamic Bundles | ✅ Implemented | High |
| 004 | PowerSync Offline | 📋 Planned | Critical |
| 005 | Electron POS | 📋 Planned | Critical |
| 006 | SaaS Governance | ✅ Implemented | High |
| 007 | Immutable Ledger | ✅ Implemented | Critical |
| 008 | ETA Integration | 🔜 Deferred | Medium |
