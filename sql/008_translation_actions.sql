BEGIN;

-- ------------------------------------------------------------------
-- Per-event word count. Always the SOURCE word count.
-- ------------------------------------------------------------------
ALTER TABLE translations
  ADD COLUMN word_count INT NOT NULL DEFAULT 0;

UPDATE translations t
   SET word_count = k.word_count
  FROM keys k
 WHERE k.id = t.key_id;

CREATE INDEX IF NOT EXISTS idx_translations_user_action
  ON translations (translated_by_user_id, revision_id, created_at DESC);

-- ------------------------------------------------------------------
-- action: how this row was produced.
-- ------------------------------------------------------------------
ALTER TABLE translations
  ADD COLUMN action TEXT NOT NULL DEFAULT 'translate';

ALTER TABLE translations
  ADD CONSTRAINT translations_action_check
  CHECK (action IN ('translate','correct','validate','self_edit','ai_draft'));

-- Backfill: every AI row is 'ai_draft'.
UPDATE translations
   SET action = 'ai_draft'
 WHERE translated_by_ai = true;

-- Backfill: in the same (key, revision, language), any non-AI row authored by
-- the same user after the first row for that user is a self_edit.
WITH ranked AS (
  SELECT id, row_number() OVER (
    PARTITION BY key_id, revision_id, language, translated_by_user_id
    ORDER BY created_at, id
  ) AS rn
    FROM translations
   WHERE translated_by_ai = false
)
UPDATE translations t
   SET action = 'self_edit'
  FROM ranked r
 WHERE t.id = r.id
   AND r.rn > 1;

COMMIT;
