-- ============================================================
-- TMS — Translation Management System
-- Schema v1 (Task 5)
-- PostgreSQL 14+
-- ============================================================
-- This file is idempotent-safe only if run on an empty database.
-- To change the schema later, add sql/002_*.sql — never edit this.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- extensions
-- ------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive emails

-- ------------------------------------------------------------
-- helper: updated_at trigger
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- USERS
-- ============================================================
CREATE TYPE user_role AS ENUM ('admin', 'lead_translator', 'translator');

CREATE TABLE users (
  id            BIGSERIAL    PRIMARY KEY,
  email         CITEXT       NOT NULL UNIQUE,
  name          TEXT         NOT NULL,
  password_hash TEXT         NOT NULL,        -- bcrypt RFC2307 string
  role          user_role    NOT NULL DEFAULT 'translator',
  is_active     BOOLEAN      NOT NULL DEFAULT true,
  created_by    BIGINT       REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_users_updated
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_users_role_active ON users(role) WHERE is_active;

-- ============================================================
-- SESSIONS  (server-side; cookie holds only the session id)
-- ============================================================
CREATE TABLE sessions (
  id          TEXT         PRIMARY KEY,       -- 64 hex chars
  user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ip          INET,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ  NOT NULL,
  revoked_at  TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user    ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

-- ============================================================
-- PROJECTS
-- ============================================================
CREATE TABLE projects (
  id                  BIGSERIAL    PRIMARY KEY,
  name                TEXT         NOT NULL,
  slug                TEXT         NOT NULL UNIQUE,
  default_source_lang TEXT         NOT NULL,  -- BCP-47: en, de, ar, …
  created_by          BIGINT       REFERENCES users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_projects_updated
BEFORE UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ------------------------------------------------------------
-- project membership
-- ------------------------------------------------------------
CREATE TYPE project_role AS ENUM ('admin', 'lead', 'translator');

CREATE TABLE project_members (
  project_id BIGINT        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id    BIGINT        NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  role       project_role  NOT NULL DEFAULT 'translator',
  added_by   BIGINT        REFERENCES users(id) ON DELETE SET NULL,
  added_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, user_id)
);

CREATE INDEX idx_pm_user ON project_members(user_id);

-- ============================================================
-- FILE GROUPS  (e.g. "auth", "dashboard" across languages)
-- ============================================================
CREATE TABLE file_groups (
  id         BIGSERIAL    PRIMARY KEY,
  project_id BIGINT       NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name       TEXT         NOT NULL,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (project_id, name)
);

-- ============================================================
-- FORMATS  (lookup table; new formats added without code change)
-- ============================================================
CREATE TABLE formats (
  code      TEXT     PRIMARY KEY,   -- 'laravel','vue','symfony',…
  label     TEXT     NOT NULL,
  file_ext  TEXT     NOT NULL,
  is_active BOOLEAN  NOT NULL DEFAULT true
);

INSERT INTO formats (code, label, file_ext) VALUES
  ('laravel', 'Laravel PHP array', 'php'),
  ('vue',     'Vue i18n JSON',     'json'),
  ('symfony', 'Symfony YAML',      'yaml'),
  ('go',      'Go JSON',           'json'),
  ('react',   'React i18next JSON','json'),
  ('angular', 'Angular JSON',      'json'),
  ('flutter', 'Flutter ARB',       'arb');

-- ============================================================
-- FILES  (one physical file = one target language)
-- ============================================================
CREATE TYPE file_status AS ENUM (
  'unassigned',
  'assigned',
  'in_progress',
  'in_review',
  'approved',
  'locked'
);

CREATE TABLE files (
  id                  BIGSERIAL    PRIMARY KEY,
  project_id          BIGINT       NOT NULL REFERENCES projects(id)    ON DELETE CASCADE,
  group_id            BIGINT                REFERENCES file_groups(id) ON DELETE SET NULL,
  name                TEXT         NOT NULL,
  format              TEXT         NOT NULL REFERENCES formats(code),
  source_lang         TEXT         NOT NULL,
  target_lang         TEXT         NOT NULL,
  is_source           BOOLEAN      NOT NULL DEFAULT false,
  status              file_status  NOT NULL DEFAULT 'unassigned',
  assigned_to_user_id BIGINT                REFERENCES users(id) ON DELETE SET NULL,
  current_revision_id BIGINT,                -- FK added after file_revisions
  created_by          BIGINT                REFERENCES users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (project_id, name, target_lang)
);

CREATE TRIGGER trg_files_updated
BEFORE UPDATE ON files
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_files_project   ON files(project_id);
CREATE INDEX idx_files_assigned  ON files(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
CREATE INDEX idx_files_status    ON files(status);
CREATE INDEX idx_files_source    ON files(project_id, is_source) WHERE is_source;

-- ============================================================
-- FILE REVISIONS  (immutability + approval scope)
-- ============================================================
CREATE TYPE revision_status AS ENUM ('open', 'in_review', 'approved', 'rejected');

CREATE TABLE file_revisions (
  id                 BIGSERIAL        PRIMARY KEY,
  file_id            BIGINT           NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  revision_number    INT              NOT NULL,
  status             revision_status  NOT NULL DEFAULT 'open',
  reason             TEXT,
  created_by_user_id BIGINT                    REFERENCES users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ      NOT NULL DEFAULT now(),
  approved_at        TIMESTAMPTZ,
  UNIQUE (file_id, revision_number)
);

CREATE INDEX idx_rev_file ON file_revisions(file_id, revision_number DESC);

ALTER TABLE files
  ADD CONSTRAINT fk_files_current_revision
  FOREIGN KEY (current_revision_id)
  REFERENCES file_revisions(id)
  ON DELETE SET NULL;

-- ============================================================
-- KEYS  (one row per translation key within a file)
-- ============================================================
CREATE TABLE keys (
  id          BIGSERIAL    PRIMARY KEY,
  file_id     BIGINT       NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  key_path    TEXT         NOT NULL,       -- 'auth.login.title'
  source_text TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (file_id, key_path)
);

CREATE INDEX idx_keys_file ON keys(file_id);
CREATE INDEX idx_keys_fts  ON keys USING GIN (to_tsvector('simple', coalesce(source_text, '')));

-- ============================================================
-- TRANSLATIONS  (append-only history)
-- ============================================================
CREATE TYPE translation_status AS ENUM (
  'empty', 'ai_draft', 'translated', 'needs_review', 'approved', 'rejected'
);

CREATE TABLE translations (
  id                    BIGSERIAL           PRIMARY KEY,
  key_id                BIGINT              NOT NULL REFERENCES keys(id)           ON DELETE CASCADE,
  revision_id           BIGINT              NOT NULL REFERENCES file_revisions(id) ON DELETE CASCADE,
  language              TEXT                NOT NULL,
  text                  TEXT,
  status                translation_status  NOT NULL DEFAULT 'empty',
  note                  TEXT,
  translated_by_user_id BIGINT                       REFERENCES users(id) ON DELETE SET NULL,
  translated_by_ai      BOOLEAN             NOT NULL DEFAULT false,
  ai_engine             TEXT,                -- 'libretranslate' | 'gemini' | …
  created_at            TIMESTAMPTZ         NOT NULL DEFAULT now()
);

CREATE INDEX idx_tr_key_rev     ON translations(key_id, revision_id);
CREATE INDEX idx_tr_rev_status  ON translations(revision_id, status);
CREATE INDEX idx_tr_lang_status ON translations(language, status);

-- ============================================================
-- APPROVALS
-- ============================================================
CREATE TYPE approval_decision AS ENUM ('approve', 'reject');

CREATE TABLE approvals (
  id          BIGSERIAL          PRIMARY KEY,
  file_id     BIGINT             NOT NULL REFERENCES files(id)          ON DELETE CASCADE,
  revision_id BIGINT             NOT NULL REFERENCES file_revisions(id) ON DELETE CASCADE,
  user_id     BIGINT             NOT NULL REFERENCES users(id)          ON DELETE CASCADE,
  decision    approval_decision  NOT NULL,
  comment     TEXT,
  created_at  TIMESTAMPTZ        NOT NULL DEFAULT now(),
  UNIQUE (revision_id, user_id)
);

CREATE INDEX idx_app_rev ON approvals(revision_id);

-- ============================================================
-- ASSIGNMENTS  (history of who was assigned what, when)
-- ============================================================
CREATE TABLE assignments (
  id            BIGSERIAL    PRIMARY KEY,
  file_id       BIGINT       NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  user_id       BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  assigned_by   BIGINT                REFERENCES users(id) ON DELETE SET NULL,
  assigned_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  unassigned_at TIMESTAMPTZ
);

CREATE INDEX idx_assign_file ON assignments(file_id, unassigned_at);
CREATE INDEX idx_assign_user ON assignments(user_id, unassigned_at);

-- ============================================================
-- NOTIFICATIONS  (in-app; email later via same table)
-- ============================================================
CREATE TYPE notification_type AS ENUM (
  'file_assigned', 'file_submitted', 'file_approved', 'file_rejected',
  'comment_added', 'revision_opened'
);

CREATE TABLE notifications (
  id          BIGSERIAL          PRIMARY KEY,
  user_id     BIGINT             NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        notification_type  NOT NULL,
  entity_type TEXT               NOT NULL,
  entity_id   BIGINT             NOT NULL,
  payload     JSONB              NOT NULL DEFAULT '{}'::jsonb,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ        NOT NULL DEFAULT now()
);

CREATE INDEX idx_notif_user_unread ON notifications(user_id) WHERE read_at IS NULL;
CREATE INDEX idx_notif_created     ON notifications(created_at DESC);

-- ============================================================
-- AUDIT LOG
-- ============================================================
CREATE TABLE audit_log (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     BIGINT                REFERENCES users(id) ON DELETE SET NULL,
  action      TEXT         NOT NULL,
  entity_type TEXT         NOT NULL,
  entity_id   BIGINT,
  old_value   JSONB,
  new_value   JSONB,
  ip          INET,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_user   ON audit_log(user_id, created_at DESC);

COMMIT;
