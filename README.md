# TMS — Translation Management System

A team-based translation management tool for i18n files (Laravel, Vue, Symfony, Go, React, Angular, Flutter).

- Backend: Perl + Mojolicious
- Frontend: Vue 3
- DB: PostgreSQL
- Workflow: translator → lead(s) → admin approval

## Status
Early development — Task 0: project scaffolding.
Schema v1 applied (`sql/001_schema.sql`).
Bootstrap admin: `carton exec -- perl script/seed_admin.pl --email=… --name=… --password=…`
Auth: POST /api/v1/auth/login, POST /api/v1/auth/logout, GET /api/v1/auth/me (session cookie).

## Database
One-command setup from zero (drops and recreates the dev DB):

    carton exec -- perl script/reset_db.pl

Requires `TMS_MODE=development` (or unset) and `TMS_DEV_ADMIN_*` in `.env`.

Apply only new migrations (safe on any environment):

    carton exec -- perl script/migrate.pl

Migrations live in `sql/` as `NNN_name.sql`, applied in lexical order.
Applied files are recorded in `schema_migrations` with a SHA-256 checksum.
**Never edit an applied migration** — the runner refuses to proceed if the checksum changed. Add a new file instead.

## Local services
Postgres runs via `docker/docker-compose.services.yml` (optional — any reachable PostgreSQL works).