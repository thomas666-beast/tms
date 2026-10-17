BEGIN;

CREATE UNIQUE INDEX uq_translations_current
  ON translations (key_id, revision_id, language, created_at);

COMMIT;
