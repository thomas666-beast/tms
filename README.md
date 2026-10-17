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

## Tests
Tests run against a separate database, `tms_test`, never against your dev DB.

One-time (or whenever you want a clean test DB):

    carton exec -- perl script/test_db.pl

Then:

    carton exec -- prove -l t

`t/testlib.pl` points `DATABASE_URL` at `tms_test` for the duration of each
test run and refuses to proceed if the resolved DB name does not end in `_test`.
Override with `TMS_TEST_DATABASE_URL` if you need a different database.

## Endpoints
Authenticated (any logged-in user):
- `GET    /api/v1/projects`
- `GET    /api/v1/projects/:id`
- `PATCH  /api/v1/projects/:id` (project admin or global admin)
- `POST   /api/v1/projects` (global admin only)
- `PATCH  /api/v1/keys/:id/translation`             (project lead, project admin, or assigned translator; body: `text?`, `status?`, `note?`)
- `GET    /api/v1/keys/:id/translation/history`
- `POST   /api/v1/files/:id/submit`          (project lead, project admin, global admin)
- `POST   /api/v1/files/:id/approve`         (project lead, project admin, global admin; not the file's assigned translator)
- `POST   /api/v1/files/:id/reject`          (same; requires `comment`)
- `GET    /api/v1/files/:id/approvals`
- `POST   /api/v1/files/:id/assign`          (project admin, global admin; body: `user_id`)
- `POST   /api/v1/files/:id/unassign`        (project admin, global admin)
- `GET    /api/v1/notifications?unread=1`
- `POST   /api/v1/notifications/read_all`
- `POST   /api/v1/notifications/:id/read`
- `GET    /api/v1/files/:id/export?revision=current|latest_approved` (returns the file in its original format)

## Local services
Postgres runs via `docker/docker-compose.services.yml` (optional — any reachable PostgreSQL works).

## Frontend (dev)

    cd frontend
    npm install
    npm run dev      # http://localhost:5173, proxies /api to :3000

Backend must be running: `carton exec -- morbo script/tms`.

Production build (`npm run build`) writes to `public/app/` — backend static serving is added in a later task.

### i18n

All UI strings live in `frontend/src/i18n/<locale>.js`.
Currently only `en` is present. To add a language, create `frontend/src/i18n/xx.js`
with the same keys, and register it in `frontend/src/i18n/index.js` (`SUPPORTED`).
