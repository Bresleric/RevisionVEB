-- RevisionVEB — ventilation charge / TVA / TTC sur les lignes de detail
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- Idempotent : peut etre relance sans risque.
--
-- Une facture non parvenue porte une contrepartie de charge, une TVA
-- recuperable et un TTC. Sans ces colonnes, la synchronisation renvoie
-- PGRST204 et la ventilation reste sur le Mac qui l'a saisie.

ALTER TABLE recon_items
    ADD COLUMN IF NOT EXISTS compte_charge TEXT             NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS montant_ht    DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS taux_tva      DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS montant_tva   DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Verification : doit lister les quatre colonnes.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'recon_items'
  AND column_name IN ('compte_charge', 'montant_ht', 'taux_tva', 'montant_tva')
ORDER BY column_name;
