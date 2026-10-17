BEGIN;

ALTER TABLE approvals
  ADD COLUMN user_role_at_time user_role;

COMMIT;
