# TMS — Translation Management System

Team translation tool for i18n files: Laravel, Vue-i18n, Symfony, Go, React, Angular, Flutter.

- **Backend:** Perl + Mojolicious
- **Frontend:** Vue 3 + Vite
- **Database:** PostgreSQL
- **Auth:** server-side sessions + per-session CSRF token
- **AI:** LibreTranslate + Gemini (pluggable)

Version: **0.1.0** — feature-complete for the initial scope.

## Table of contents

- [Roles](#roles)
- [Workflow](#workflow)
- [Quick start](#quick-start)
- [Tests](#tests)
- [Database](#database)
- [Endpoints](#endpoints)
- [Project layout](#project-layout)
- [Extending](#extending)
- [Known issues](#known-issues)

## Roles

| Role | What they can do |
|---|---|
| **admin** | Full access. Creates users and projects. Part of every approval. |
| **lead_translator** | Reviews and approves translations. Can be a project lead. |
| **translator** | Translates files assigned to them. |

Project-level roles are separate from global roles:

| Project role | What it allows |
|---|---|
| **admin** (project) | Manage members, upload files, assign translators, review |
| **lead** (project) | Review and approve translations |
| **translator** (project) | Translate assigned files |

## Workflow

```text
unassigned -> assigned -> in_progress -> in_review -> approved
                               ^
                               +-- rejected (opens a new revision)
```

**Approval rule:** a revision is approved only with **two or more approvers**, at least one of them a **global admin**. The file's own assigned translator cannot approve it.

Rejecting a revision opens a new one in the `open` state, so the translator can continue without losing history.

## Quick start

### 1. Backend

```sh
cp .env.example .env
# edit .env:
#   TMS_SECRET              long random string
#   DATABASE_URL            postgres://user:pass@host:port/db
#   TMS_DEV_ADMIN_EMAIL     admin email to seed
#   TMS_DEV_ADMIN_NAME
#   TMS_DEV_ADMIN_PASSWORD

carton install
carton exec -- perl script/reset_db.pl
carton exec -- morbo script/tms
# http://127.0.0.1:3000
```

### 2. Frontend

```sh
cd frontend
npm install
npm run dev
# http://localhost:5173, proxies /api to :3000
```

Production build:

```sh
npm run build
# writes public/app/
```

### 3. Optional services

```sh
docker compose -f docker/docker-compose.services.yml up -d postgres
docker compose -f docker/docker-compose.services.yml up -d libretranslate
```

## Tests

```sh
carton exec -- perl script/test_db.pl
carton exec -- prove -l t
```

`t/testlib.pl` points `DATABASE_URL` at `tms_test` for every test run and refuses to run against a database whose name does not end in `_test`.

## Database

- `script/migrate.pl` applies new `sql/NNN_*.sql` files in lexical order. It refuses to re-run a file whose checksum changed.
- `script/reset_db.pl` drops and recreates the dev database, migrates, and seeds the admin. Only runs in `development` mode.
- `script/test_db.pl` recreates `tms_test`, migrates, and seeds the admin.
- `script/seed_admin.pl` creates or updates one admin user. There is no public registration.

## Endpoints

### Public

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `GET  /api/v1/auth/me`
- `GET  /api/v1/health`

### Authenticated

Dashboard:

- `GET /api/v1/me/dashboard`

Projects:

- `GET   /api/v1/projects`
- `GET   /api/v1/projects/:id`
- `PATCH /api/v1/projects/:id`

Project members:

- `GET    /api/v1/projects/:id/members`
- `POST   /api/v1/projects/:id/members`
- `PATCH  /api/v1/projects/:id/members/:user_id`
- `DELETE /api/v1/projects/:id/members/:user_id`
- `GET    /api/v1/projects/:id/candidates`

Files:

- `POST /api/v1/projects/:id/files` (multipart upload)
- `GET  /api/v1/projects/:id/files`
- `GET  /api/v1/files/:id`
- `GET  /api/v1/files/:id/keys` (optional `?status=`, `?with_previous=1`)
- `GET  /api/v1/files/:id/export` (optional `?revision=latest_approved`)
- `POST /api/v1/files/:id/assign`
- `POST /api/v1/files/:id/unassign`

Translations:

- `PATCH /api/v1/keys/:id/translation`
- `GET   /api/v1/keys/:id/translation/history`

Workflow:

- `POST /api/v1/files/:id/submit`
- `POST /api/v1/files/:id/approve`
- `POST /api/v1/files/:id/reject`
- `GET  /api/v1/files/:id/approvals`

AI:

- `POST /api/v1/keys/:id/ai_translate`
- `POST /api/v1/files/:id/ai_translate`

Notifications:

- `GET  /api/v1/notifications`
- `POST /api/v1/notifications/:id/read`
- `POST /api/v1/notifications/read_all`

### Admin only

- `GET   /api/v1/users`
- `POST  /api/v1/users`
- `PATCH /api/v1/users/:id`
- `POST  /api/v1/users/:id/password`
- `POST  /api/v1/projects`

## Project layout

```text
tms/
  lib/
    TMS/
      Controller/   HTTP layer, one module per resource
      Plugin/       Mojolicious plugins (DB, Auth)
      Adapter/      File format adapters (laravel, vue, ...)
      Engine/       AI translation engines (libretranslate, gemini)
      Service/      Business logic (Notifier, ...)
      Util/         Small helpers
  script/
    tms             dev server launcher
    migrate.pl
    reset_db.pl
    test_db.pl
    seed_admin.pl
    tidy.pl
  sql/              numbered migrations
  t/                tests
  frontend/         Vue 3 app
  docker/           optional service compose files
```

## Extending

### Add a file format

1. Create `lib/TMS/Adapter/<Name>.pm` implementing `name`, `extension`, `parse`, and `serialize`. Use `with 'TMS::Adapter::Role';`.
2. Register the module in `lib/TMS/Adapter.pm`.
3. Add a row to the `formats` table via a new migration `sql/NNN_*.sql`.
4. Add a test in `t/`.

### Add an AI engine

1. Create `lib/TMS/Engine/<Name>.pm` implementing `name` and `translate`. Use `with 'TMS::Engine::Role';`.
2. Register the module in `lib/TMS/Engine.pm`.
3. Add the required env var (for example an API key) to `.env.example` and read it in the engine.

### Add a UI language

1. Create `frontend/src/i18n/<code>.js` with the same keys as `en.js`.
2. Register it in `frontend/src/i18n/index.js` under `SUPPORTED`.

## Known issues

- Frontend session persistence on hard reload requires installing the router **after** `fetchMe()` completes. Keep this order in `frontend/src/main.js`:

```js
const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(i18n)

const auth = useAuthStore(pinia)
await auth.fetchMe()

app.use(router)
await router.isReady()
app.mount('#app')
```
