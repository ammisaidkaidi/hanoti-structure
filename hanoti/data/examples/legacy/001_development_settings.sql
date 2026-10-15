-- Development seed. Apply after migrations; safe to rerun.
INSERT INTO app_settings (key, value)
VALUES ('workspace', '{"name":"Hanouti"}'::jsonb)
ON CONFLICT (key) DO NOTHING;
