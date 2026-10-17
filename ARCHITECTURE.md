# Architecture

## Stack
- Backend: Perl + Mojolicious
- Frontend: Vue 3 (in `frontend/`, builds to `public/`)
- DB: PostgreSQL (raw SQL, `Mojo::Pg`, no ORM)
- AI: pluggable engines (LibreTranslate, Gemini, …)

## Namespace
Top-level Perl namespace: `TMS`.

## Folder layout

| Path | Purpose |
|---|---|
| `lib/TMS.pm` | App class (Mojolicious subclass) |
| `lib/TMS/Controller/` | HTTP layer — one module per resource |
| `lib/TMS/Plugin/` | Mojolicious plugins (DB, Auth, CSRF, Notifier) |
| `lib/TMS/Adapter/` | File format adapters (parse + serialize) |
| `lib/TMS/Engine/` | Translation engines (AI or manual) |
| `lib/TMS/Service/` | Business logic (Workflow, Notifier, Audit) |
| `lib/TMS/Util/` | Small helpers |
| `script/` | Executable scripts (dev server, seed admin) |
| `sql/` | Raw SQL migrations |
| `t/` | Tests (Perl) |
| `frontend/` | Vue 3 app (its own npm project) |
| `public/` | Static assets + built frontend |
| `docker/` | Optional service compose files |

## Roles
- `admin` — full access, final approval, user management
- `lead_translator` — review & approve translator work
- `translator` — translate assigned files only

## Workflow
File states: `unassigned → assigned → in_progress → in_review → approved → locked`
Approval rule: a file is `approved` only with **≥ 2 approvers**, at least one of them `admin`, none being the translator of that file.

## Auth
Server-side sessions stored in Postgres, delivered via `HttpOnly` cookie, CSRF-protected.
No public registration — admins are seeded via `script/seed_admin.pl`; only admins create other users.

## Format adapters (planned)
`laravel`, `vue`, `symfony`, `go`, `react`, `angular`, `flutter`.

## Translation engines (planned)
`libretranslate` (self-hosted, free), `gemini` (free tier), `manual` (no-op, for pure human flow). New engines = new module in `lib/TMS/Engine/`.
