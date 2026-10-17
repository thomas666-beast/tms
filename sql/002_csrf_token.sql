-- ============================================================
-- TMS — schema v2 (Task 9): CSRF token per session
-- ============================================================
BEGIN;

ALTER TABLE sessions
  ADD COLUMN csrf_token TEXT;

-- All existing sessions become invalid; their CSRF token is NULL,
-- so any mutation with them will be rejected by the CSRF check.
-- That's exactly what we want after a deploy.

CREATE INDEX idx_sessions_csrf ON sessions(csrf_token) WHERE csrf_token IS NOT NULL;

COMMIT;
