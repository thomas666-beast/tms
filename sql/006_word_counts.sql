BEGIN;

ALTER TABLE keys ADD COLUMN word_count INT NOT NULL DEFAULT 0;

UPDATE keys
   SET word_count = COALESCE(
     array_length(
       regexp_split_to_array(
         regexp_replace(trim(both from coalesce(source_text, '')), '\s+', ' ', 'g'),
         ' '
       ),
       1
     ),
     0
   );

CREATE INDEX idx_keys_word_count ON keys(file_id, word_count);

COMMIT;
