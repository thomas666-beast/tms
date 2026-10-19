BEGIN;

CREATE INDEX IF NOT EXISTS idx_translations_key_rev_created
  ON translations (key_id, revision_id, created_at DESC);

COMMIT;
