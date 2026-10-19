BEGIN;

ALTER TABLE users
  ADD COLUMN notification_preferences JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMIT;
