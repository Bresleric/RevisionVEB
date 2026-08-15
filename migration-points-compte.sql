-- RevisionVEB — rattachement des points en suspens et des notes a un compte
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- Idempotent : peut etre relance sans risque.
--
-- Sans cette colonne, la synchronisation renvoie une erreur PGRST204
-- (« colonne absente ») et les points saisis restent sur le Mac qui les a
-- saisis.

ALTER TABLE points_en_suspens
    ADD COLUMN IF NOT EXISTS account_number TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS points_en_suspens_compte_idx
    ON points_en_suspens (exercice_id, account_number);

-- Verification : doit lister la colonne account_number.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'points_en_suspens'
ORDER BY ordinal_position;
