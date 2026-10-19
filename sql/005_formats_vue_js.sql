BEGIN;

INSERT INTO formats (code, label, file_ext)
VALUES ('vue_js', 'Vue i18n JavaScript', 'js')
ON CONFLICT (code) DO NOTHING;

COMMIT;
