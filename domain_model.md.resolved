# Phase 1: Domain Modeling

Architecture-level definitions for the Wholesale Commerce Platform.

## 1. Bounded Contexts (Core Domains)

### A. Identity & Tenancy (The Foundation)
**Responsibility**: Managing the multi-tenant isolation, user identity, and granular access control (RBAC).  
**Core Entities**: 
- `Tenant`: The organizational root.
- `User`: Identity across tenants.
- `Profile`: Tenant-specific identity and Role.
- `Role/Permission`: Access definitions.

### B. Catalog Domain (Abstract Product Definition)
**Responsibility**: Defining *what* can be sold. It deals with definitions, not physical stock.  
**Core Entities**:
- `Product`: Abstract definition (e.g., "Cotton T-Shirt").
- `ProductVariant`: Concrete variation (e.g., "Size: XL, Color: Black").
- `UnitDefinition`: Scaling/packaging definitions (e.g., "Carton of 12").
- `Category/Attribute`: Taxonomies for classification.

### C. Inventory Domain (Stock & Movement)
**Responsibility**: Managing the physical existence and flow of goods across locations.  
**Core Entities**:
- `Location`: Physical or logical site (Warehouse, Branch, Van).
- `StockLevel`: Snapshot of quantity at a specific location/variant/unit.
- `Reservation`: Temporary lock on stock.
- `MovementRecord`: Foundation for the audit trail of any stock change.

### D. Sales & Transaction Domain (The "Order")
**Responsibility**: Managing the lifecycle of a commercial exchange.  
**Core Entities**:
- `Order`: The central commercial document.
    - *Relations*: Belongs to a `Customer` (from CRM Domain).
- `OrderLine`: Individual items and quantities.
- `Transaction`: Financial representation of the order.
- `StatusLifecycle`: State machine for order progression.

### E. Pricing & Rules Domain (The Logic Engine)
**Responsibility**: Calculating commercial values based on dynamic contextual rules.  
**Core Entities**:
- `PricingRule`: Condition-based price logic (Groups, Volume, Time).
- `PriceTier`: Grouping for customers or units.

### F. Event Infrastructure Domain (The Messenger)
**Responsibility**: Decoupling domains by emitting and persisting business occurrences.  
**Core Entities**:
- `DomainEvent`: Representation of a business fact that has occurred.
- `EventLog`: Immutable ledger of events.

### G. Customer & Relationship Domain (CRM)
**Responsibility**: Managing the merchant's client base, debt, and grouping strategies.
**Core Entities**:
- `Customer`: The buyer entity (B2B or B2C).
    - Fields: `customer_id`, `name`, `email`, `tenant_id`.
- `CustomerGroup`: Classification for pricing rules (e.g., VIP, Wholesaler).
- `CreditLimit`: Financial safety boundaries for B2B.

---

## 2. Domain Responsibilities & Boundaries

- **Isolation**: Each domain owns its data. No domain can directly modify the physical state of another domain except through events or strictly defined service calls.
- **Independence**: The **Catalog** doesn't know about **Inventory** levels. It only knows what is *possible* to stock.
- **Consistency**: **Inventory** and **Sales** are kept in sync via transactional atomic operations within the Core.

---

## 3. Explicitly NOT Part of the Core

The following are **Modules** or **Peripherals**, NOT Core responsibilities:

1. **POS Logic**: UI flows, offline synchronization mechanisms, local hardware integration (scanners/printers).
2. **Storefront (B2B/B2C)**: Theme management, customer shopping experience, frontend cart logic.
3. **Specific Tax Engines**: Calculation logic for Egyptian VAT vs. Saudi ZATCA vs. US Sales Tax.
4. **Integration Adapters**: WhatsApp API clients, Accounting software connectors (QuickBooks/Odoo), Shipping carrier APIs.
5. **Analytics & BI**: Heavy data processing for reports (consumes Core Events but doesn't live in Core).
6. **Billing (Platform SaaS)**: Subscription management for the Merchants themselves (belongs to the Super Admin app).
