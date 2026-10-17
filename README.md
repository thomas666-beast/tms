# TMS — Translation Management System

A team translation tool for i18n files (Laravel, Vue-i18n, Symfony, Go, React, Angular, Flutter).

- Backend: Perl + Mojolicious
- Frontend: Vue 3 + Vite
- DB: PostgreSQL
- Auth: server-side sessions + per-session CSRF token
- AI: LibreTranslate + Gemini (pluggable)

## Roles

- **admin** — full access, creates users and projects, final approval
- **lead_translator** — reviews and approves, can be a project lead
- **translator** — translates files assigned to them

## Workflow

`unassigned → assigned → in_progress → in_review → approved`  
Rejection opens a new revision (`open`) so translation can continue.

Approval requires **2 approvals**, at least one from a **global admin**.  
A file's own assigned translator cannot approve it.

## Quick start

### 1. Backend

    cp .env.example .env
    # edit .env: TMS_SECRET, DATABASE_URL, TMS_DEV_ADMIN_*
    carton install
    carton exec -- perl script/reset_db.pl
    carton exec -- morbo script/tms
    # http://127.0.0.1:3000

### 2. Frontend

    cd frontend
    npm install
    npm run dev
    # http://localhost:5173, proxies /api to :3000

Production build:

    npm run build   # writes public/app/

### 3. Optional services

    docker compose -f docker/docker-compose.services.yml up -d postgres
    docker compose -f docker/docker-compose.services.yml up -d libretranslate

## Tests

    carton exec -- perl script/test_db.pl   # recreate tms_test
    carton exec -- prove -l t

## Database

- `script/migrate.pl` — apply new `sql/NNN_*.sql` files
- `script/reset_db.pl` — drop + recreate dev DB, migrate, seed admin (dev only)

## Extending

**Add a format** — new module in `lib/TMS/Adapter/`, register in `lib/TMS/Adapter.pm`. Rows in `formats` table also need the new `code`.

**Add an AI engine** — new module in `lib/TMS/Engine/` implementing `name` and `translate`, register in `lib/TMS/Engine.pm`.

**Add a language (UI)** — new `frontend/src/i18n/<code>.js` with the same keys, register in `frontend/src/i18n/index.js`.

## Status

Feature-complete for the initial scope: users, projects, members, file upload, translation editor, AI translation, workflow with 2-approver quorum, approvals, in-app notifications, export, dashboard, admin user management.
