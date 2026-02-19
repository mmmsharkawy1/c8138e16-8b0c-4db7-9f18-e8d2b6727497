# TAGER ERP - Enterprise SaaS Platform

Multi-tenant wholesale/retail ERP with offline-first POS capabilities.

## 🏗️ Project Structure

```
tager-erp/
├── apps/
│   ├── dashboard/    # Next.js 14 Admin Dashboard
│   └── pos/          # Electron POS Application
├── packages/
│   ├── shared/       # Shared types & utilities
│   └── database/     # Supabase client & services
└── supabase/
    └── migrations/   # Database schema & functions
```

## 📦 Tech Stack

- **Monorepo:** Turborepo + pnpm
- **Database:** Supabase (PostgreSQL)
- **Backend:** Next.js API Routes
- **Frontend:** Next.js 14 (App Router)
- **POS:** Electron + PowerSync
- **Auth:** Supabase Auth + MFA

## 🚀 Quick Start

### Prerequisites
- Node.js >= 18
- pnpm >= 8
- Supabase CLI

### Installation

```bash
# Install dependencies
pnpm install

# Setup Supabase
cd supabase
supabase init
supabase start

# Apply migrations
supabase db push

# Run development servers
pnpm dev
```

## 📚 Documentation

See `/docs` for detailed documentation on:
- Database schema
- API endpoints
- Component library
- Deployment guide

## 🔐 Security

- Multi-tenant isolation via RLS
- MFA for all accounts
- API rate limiting
- Audit logging

---

**Status:** Phase 5 - Active Development  
**Version:** 1.0.0-alpha
