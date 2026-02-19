# ANTI-GRAVITY SYSTEMS MASTER FRAMEWORK v2.1
**TAGER ERP Edition - Single Model Execution**

---

## A) Executive Summary

**Purpose:** إطار شامل لتشغيل وإدارة وتنسيق جميع مراحل بناء TAGER ERP (Enterprise SaaS + Offline POS + Multi-Niche Support).

**Scope:** يشمل المعمارية، التنفيذ، قواعد التطوير، ومعايير الجودة.

**Core Principles:**
1. **Consistency First** - نفس الأنماط عبر كل الكود
2. **Single Source of Truth** - Database هو المرجع الوحيد
3. **Unified Execution** - نموذج واحد يغطي جميع الأدوار
4. **Zero-Ambiguity Outputs** - كل مخرج له Acceptance Criteria واضحة
5. **Phase-Driven Development** - كل مرحلة لها Gate Checks

---

## B) Architecture Master Framework

### 1. System Layers (6 Layers)

```
┌─────────────────────────────────────────┐
│  6. UX Orchestration Layer              │  Onboarding, Niche Wizards
├─────────────────────────────────────────┤
│  5. SaaS Governance Layer               │  Plans, Limits, Feature Flags
├─────────────────────────────────────────┤
│  4. POS Native Layer                    │  Electron, Hardware APIs
├─────────────────────────────────────────┤
│  3. Application Layer                   │  Next.js 14 + Turborepo
├─────────────────────────────────────────┤
│  2. Sync Layer                          │  PowerSync (Offline-First)
├─────────────────────────────────────────┤
│  1. Data Layer                          │  Supabase + SQL + RLS
└─────────────────────────────────────────┘
```

### 2. Migration Pipeline (STRICT ORDER)

**CRITICAL:** Execute in exact order to avoid FK constraint errors.

```sql
supabase/migrations/
├── 001_core_schema.sql              -- 22 tables
├── 002_seed_niche_templates.sql     -- 3 business types
├── 003_saas_governance.sql          -- Limit enforcement functions
├── 004_rls_policies.sql             -- 38 security policies
├── 005_core_functions.sql           -- 11 inventory/sales functions
├── 006_bundle_functions.sql         -- sell_bundle()
└── 007_seed_subscription_plans.sql  -- 4 pricing tiers
```

### 3. Folder Structure Standard (Turborepo)

```
wholesale-platform/
├── apps/
│   ├── dashboard/          # Merchant Management (Next.js 14)
│   ├── pos/                # POS PWA (Next.js 14 + Electron)
│   └── storefront/         # B2B Portal (Next.js 14)
├── packages/
│   ├── core/               # Supabase Client, Services, PowerSync
│   ├── shared/             # Zod Schemas, Types, Constants
│   └── ui/                 # Shadcn Components (Premium Design)
├── supabase/
│   ├── migrations/         # 7 SQL files (numbered)
│   └── seed/               # Test/Demo data
├── electron/               # POS Hardware Wrapper
├── docs/
│   ├── ADR/                # Architecture Decision Records
│   ├── API/                # API Documentation
│   └── GUIDES/             # User/Developer Guides
└── turbo.json
```

---

## C) The Execution Playbook

### 1. Deliverable Templates (Standard Artifacts)

Every phase must produce these artifacts:

| Artifact | Purpose |
|----------|---------|
| **ADR (Architecture Decision Record)** | Document major decisions |
| **Schema Map** | ER Diagram + Table specs |
| **Feature Dependencies** | Prerequisites graph |
| **State Report** | Current system status |
| **Phase Plan** | Step-by-step execution plan |
| **Task Checklist** | Granular TODO list |
| **Test Plan** | Verification scenarios |

### 2. Blueprint Format (Every Document Must Have)

```markdown
# [Document Title]

## Objective
[What this achieves]

## Inputs Required
- Input 1
- Input 2

## Steps
1. Step 1
2. Step 2

## Outputs
- Output 1
- Output 2

## Verification Checklist
- [ ] Check 1
- [ ] Check 2

## Acceptance Criteria
✅ Success looks like...
```

### 3. Progress Gates (Phase Transitions)

| Gate | Criteria |
|------|----------|
| **Gate 0: Schema Integrity** | All 22 tables created, FK constraints valid, RLS enabled (38 policies) |
| **Gate 1: Function Integrity** | All 15 functions execute without errors, tenant isolation verified |
| **Gate 2: Sync Readiness** | PowerSync rules deployed, client connects successfully |
| **Gate 3: UI Contract** | All API endpoints defined, TypeScript types generated |
| **Gate 4: SaaS Governance** | Subscription limits enforced in RLS, feature flags working |
| **Gate 5: POS Hardware Compliance** | Printer prints, scanner scans, drawer opens |
| **Gate 6: E2E Verification** | All user flows tested, no critical bugs |

---

## D) Unified Development Protocol

### Execution Strategy

1. **Single Model Execution:** نموذج واحد يتولى جميع المهام (Architecture, Coding, QA).
2. **Sequential Steps:** عدم الانتقال لخطوة تالية قبل التأكد من سابقتها.
3. **Self-Correction:** المراجعة الذاتية لكل مخرج قبل تسليمه.

### Communication Rules

1. **Structured Outputs Only** - No narrative text in technical docs
2. **Use Templates** - Follow Blueprint Format for all deliverables
3. **Version Everything** - All files have version headers
4. **Cross-Reference** - Link related documents explicitly

### Validation Protocol

Before marking any task as complete:
1. Verify against Acceptance Criteria.
2. Ensure no regressions in previous steps.
3. Check alignment with Master Framework.

---

## E) Output Standards

### 1. Naming Conventions

| Context | Convention | Example |
|---------|------------|---------|
| SQL Tables | `snake_case` | `product_bundles` |
| SQL Functions | `snake_case()` | `sell_bundle()` |
| Folders | `kebab-case` | `apps/pos` |
| TypeScript Types | `PascalCase` | `ProductBundle` |
| Variables | `camelCase` | `parentVariantId` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_RETRY_ATTEMPTS` |
| Components | `PascalCase.tsx` | `OnboardingWizard.tsx` |

### 2. File Extensions

| Type | Extension | Tool |
|------|-----------|------|
| Documentation | `.md` | Markdown |
| Schema | `.sql` | PostgreSQL |
| TypeScript Code | `.ts` | TypeScript |
| React Components | `.tsx` | TypeScript + JSX |
| Config | `.json` | JSON |
| Env Variables | `.env.local` | Dotenv |

### 3. UI Standards

**CRITICAL:** TAGER ERP must have **premium, stunning design**.

- **Component Library:** Shadcn UI (no other libraries)
- **Styling:** Tailwind CSS (no inline styles, use `cn()` utility)
- **Colors:** HSL-based, curated palettes (avoid generic red/blue/green)
- **Typography:** Google Fonts (Inter, Roboto, or Outfit)
- **Animations:** Framer Motion for micro-interactions
- **Icons:** Lucide React
- **Dark Mode:** Mandatory support
- **Responsive:** Mobile-first design

**Forbidden:**
- ❌ Inline styles
- ❌ Plain colors (use CSS variables)
- ❌ Generic UI (must wow users)

---

## F) Phase-by-Phase System (TAGER ERP)

### Phase 0: Foundation & Planning ✅ COMPLETE
**Duration:** 5 days

**Deliverables:**
- [x] Domain Model
- [x] Core Schema (22 tables)
- [x] RLS Policies (38 policies)
- [x] Core Functions (15 functions)
- [x] SaaS Governance
- [x] Niche Templates
- [x] Bundle Engine
- [x] Architecture Decisions
- [x] Schema Map
- [x] Feature Dependencies

**Gate Check:** Schema Integrity ✅

---

### Phase 1: Infrastructure Setup ⏳ NEXT
**Duration:** 2 days

**Tasks:**
- [ ] Create Supabase project
- [ ] Apply all 7 migrations
- [ ] Verify FK constraints
- [ ] Test RLS policies
- [ ] Enable MFA
- [ ] Configure JWT claims

**Deliverables:**
- [ ] Supabase credentials
- [ ] Migration logs
- [ ] RLS test results

**Gate Check:** Function Integrity

---

### Phase 2: Monorepo & Sync Layer 📋 PLANNED
**Duration:** 3 days

**Tasks:**
- [ ] Initialize Turborepo
- [ ] Setup PowerSync instance
- [ ] Configure sync rules
- [ ] Build Core package
- [ ] Generate TypeScript types from DB

**Deliverables:**
- [ ] Monorepo structure
- [ ] PowerSync config
- [ ] Type definitions

**Gate Check:** Sync Readiness

---

### Phase 3: Onboarding & Governance UI 📋 PLANNED
**Duration:** 3 days

**Tasks:**
- [ ] Onboarding Wizard UI
- [ ] Niche selection screen
- [ ] Tenant settings API (Niche, Branding, Theme)
- [ ] Subscription management UI
- [ ] Feature flag UI
- [ ] Branding Configuration UI (Logo, Colors)

**Deliverables:**
- [ ] Onboarding flow
- [ ] Admin dashboard mockups

**Gate Check:** UI Contract

---

### Phase 4: POS Application 📋 PLANNED
**Duration:** 4 days

**Tasks:**
- [ ] Build POS UI (Next.js)
- [ ] Electron wrapper
- [ ] Printer integration
- [ ] Scanner integration
- [ ] Cash drawer integration
- [ ] Offline cart management

**Deliverables:**
- [ ] POS app (working offline)
- [ ] Hardware integration test report

**Gate Check:** POS Hardware Compliance

---

### Phase 5: Bundle Management & Advanced Features 📋 PLANNED
**Duration:** 2 days

**Tasks:**
- [ ] Bundle Builder UI
- [ ] Test sell_bundle() function
- [ ] Multi-unit conversion UI
- [ ] Stock reservation UI

**Deliverables:**
- [ ] Bundle management screen
- [ ] Test results

**Gate Check:** SaaS Governance

---

### Phase 6: Testing & QA 📋 PLANNED
**Duration:** 3 days

**Tasks:**
- [ ] E2E tests (Playwright)
- [ ] RLS audit
- [ ] Load tests
- [ ] Security scan
- [ ] Performance benchmarks

**Deliverables:**
- [ ] Test coverage report
- [ ] Security audit report
- [ ] Performance metrics

**Gate Check:** E2E Verification

---

### Phase 7: Launch Preparation 📋 PLANNED
**Duration:** 2 days

**Tasks:**
- [ ] User documentation
- [ ] API documentation
- [ ] Deployment guide
- [ ] Training videos
- [ ] Launch checklist

**Deliverables:**
- [ ] Complete documentation
- [ ] Launch-ready system

**Gate Check:** Production Readiness

---

## G) Quality Assurance Framework

### 1. Code Review Checklist

Every PR must pass:
- [ ] TypeScript strict mode (no `any`)
- [ ] All tests passing
- [ ] No console.log in production code
- [ ] Proper error handling
- [ ] Security best practices (no SQL injection, XSS)
- [ ] RLS verified for new queries
- [ ] Performance acceptable (< 200ms API response)

### 2. Testing Pyramid

```
    ┌─────────────┐
    │   E2E (10%) │  Playwright
    ├─────────────┤
    │ Integration  │  Vitest + Supabase Test DB
    │    (30%)     │
    ├─────────────┤
    │   Unit       │  Vitest (Functions, Utils)
    │   (60%)      │
    └─────────────┘
```

### 3. Security Checklist

- [ ] RLS enabled on all tables
- [ ] No service_role key in client code
- [ ] MFA enforced for owners
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (sanitize inputs)
- [ ] CSRF protection (Next.js middleware)
- [ ] Rate limiting (Supabase Edge Functions)

---

## H) TAGER ERP Specific Requirements

### 1. Niche Support

TAGER ERP must support dynamic product schemas for:
- **Clothing** (color, size, material)
- **Auto Parts** (part_number, car_model, engine_type)
- **FMCG** (expiry_date, batch_number, brand)

Stored in JSONB: `products.metadata` and `product_variants.attributes`

### 2. ETA Integration (Phase 3 - Future)

Egyptian Tax Authority e-invoicing will be added later. Schema is ready but API integration deferred.

### 3. Offline-First Mandates

- **100% POS uptime** - Must work without internet
- **PowerSync conflict resolution** - Last-Write-Wins with server authority
- **Local storage quota** - SQLite database (recommended < 100MB)

---

## I) Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-09 | Initial framework |
| 2.0 | 2026-02-10 | Added TAGER specifics, Quality framework, 7 migrations |
| 2.1 | 2026-02-10 | Unified single-model execution protocol |
| 2.2 | 2026-02-12 | Race condition fixes, SKU partial index, concurrency test suite |

---

## J) Technical Implementation Details

### 1. Race Condition Prevention in Stock Reservations

The `reserve_stock()` function implements a comprehensive race condition prevention strategy:

#### Locking Strategy (3-Layer Protection)

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: PostgreSQL Advisory Lock (Transaction-scoped)         │
│  - Prevents concurrent reservations for same variant+location   │
│  - Uses SHA-256 hash to generate unique 64-bit lock key         │
│  - Automatically released at transaction end                    │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Row-Level Lock on stock_levels (FOR UPDATE)           │
│  - Locks physical stock rows during reservation                 │
│  - Prevents concurrent modifications to stock quantities        │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Row-Level Lock on stock_reservations (FOR UPDATE)     │
│  - Locks existing reservation rows                              │
│  - Ensures atomic availability calculation                      │
└─────────────────────────────────────────────────────────────────┘
```

#### Implementation Code Pattern

```sql
-- Generate deterministic lock key
v_lock_key := get_stock_lock_key(p_variant_id, p_location_id);

-- Acquire transaction-level advisory lock
PERFORM pg_advisory_xact_lock(v_lock_key);

-- Lock stock levels
PERFORM 1 FROM stock_levels 
WHERE tenant_id = p_tenant_id 
  AND variant_id = p_variant_id 
  AND location_id = p_location_id
FOR UPDATE;

-- Lock reservations
PERFORM 1 FROM stock_reservations
WHERE tenant_id = p_tenant_id
  AND variant_id = p_variant_id
  AND location_id = p_location_id
FOR UPDATE;
```

### 2. SKU Unique Constraint with Soft Delete Support

#### Problem Statement
Standard `UNIQUE` constraints don't respect soft deletes, preventing SKU reuse after deletion.

#### Solution: Partial Unique Index

```sql
-- Removed table-level constraint: UNIQUE(tenant_id, sku)
-- Replaced with partial index:
CREATE UNIQUE INDEX idx_variants_sku_active 
    ON product_variants(tenant_id, sku) 
    WHERE deleted_at IS NULL;
```

#### Behavior Matrix

| Scenario | Active Record Exists | Soft-Deleted Record Exists | New SKU Allowed? |
|----------|---------------------|---------------------------|------------------|
| New SKU | No | No | ✅ Yes |
| New SKU | No | Yes | ✅ Yes (reuse allowed) |
| New SKU | Yes | No | ❌ No (conflict) |
| Restore Deleted | Yes | Yes | ❌ No (conflict) |

### 3. Concurrency Test Suite

Located in `test_inventory_concurrency.sql`, includes:

| Test Category | Tests | Purpose |
|---------------|-------|---------|
| SKU Integrity | 3 tests | Verify unique constraint with soft delete |
| Race Condition | 5 tests | Verify locking mechanisms |
| Audit Trail | 1 test | Verify stock movement logging |
| Multi-Unit | 1 test | Verify unit conversion |
| Stress Test | Procedure | Concurrent reservation simulation |

#### Running Tests

```sql
-- Run all tests
SELECT * FROM run_all_inventory_tests();

-- Run stress test (from multiple sessions)
CALL stress_test_concurrent_reservations(100);

-- Cleanup test data
SELECT cleanup_test_data();
```

### 4. New Database Objects

| Object Type | Name | Purpose |
|-------------|------|---------|
| Function | `get_stock_lock_key(variant_id, location_id)` | Generate advisory lock key |
| Index | `idx_stock_reservations_variant_loc` | Support reservation locking |
| Index | `idx_stock_levels_tenant_variant_loc` | Support stock level locking |
| Index | `idx_variants_sku_active` | Unique SKU with soft delete |

### 5. Migration Execution Order (Updated)

```sql
supabase/migrations/
├── 001_core_schema.sql              -- 22 tables + new indexes
├── 002_seed_niche_templates.sql     -- 3 business types
├── 003_saas_governance.sql          -- Limit enforcement functions
├── 004_rls_policies.sql             -- 38 security policies
├── 005_core_functions.sql           -- 15 functions (updated reserve_stock)
├── 006_bundle_functions.sql         -- sell_bundle()
├── 007_seed_subscription_plans.sql  -- 4 pricing tiers
└── 008_test_inventory_concurrency.sql -- Concurrency test suite (optional)
```

---


---

## H) Phase 8: AI & Automation (Future Extension) 🔮
**Duration:** Ongoing

**Tasks:**
- [ ] AI Merchant Assistant (Sales Analysis)
- [ ] Customer Chatbot (Availability & Pricing)
- [ ] Automated Stock Alerts
- [ ] Predictive Ordering

**Deliverables:**
- [ ] AI Module Integration
- [ ] Chatbot API

**Gate Check:** AI Safety & Accuracy

---

## J) Appendix: Quick Reference

### Migration Execution Commands
```bash
# Apply all migrations
supabase db push

# Rollback last migration
supabase db reset

# Generate TypeScript types
supabase gen types typescript --local > packages/shared/src/types/database.ts
```

### PowerSync Connection
```typescript
await db.connect({
  powerSyncUrl: process.env.POWERSYNC_URL,
  token: supabaseSession.access_token
});
```

### RLS Testing
```sql
-- Test as specific user
SET LOCAL request.jwt.claims = '{"sub": "user-uuid", "app_metadata": {"tenant_id": "tenant-uuid"}}';
SELECT * FROM products; -- Should only return tenant's products
```

---

**END OF FRAMEWORK v2.1**

**Status:** ✅ CERTIFIED FOR PRODUCTION USE  
**Execution Model:** Single Unified Model  
**Next Review:** After Phase 7 completion
