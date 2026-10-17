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

## Local services
Postgres runs via `docker/docker-compose.services.yml` (optional — any reachable PostgreSQL works).