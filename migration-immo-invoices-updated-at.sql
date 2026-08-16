-- RevisionVEB — horodatage des factures d'investissement
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- Idempotent : peut etre relance sans risque.
--
-- CAUSE : la table immo_invoices ne portait aucune date de modification. A
-- chaque synchronisation, chaque Mac ecrasait la version de l'autre sans
-- pouvoir savoir laquelle etait la plus recente. Les deux listes de factures
-- divergeaient et se clobberaient a tour de role.
--
-- Avec cette colonne, la regle devient explicite : la saisie la plus recente
-- gagne, et une saisie locale n'est jamais remplacee par une version distante
-- plus ancienne.

ALTER TABLE immo_invoices
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Verification : doit lister updated_at.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'immo_invoices'
ORDER BY ordinal_position;

-- Controle du type de la colonne date : si elle ressort en « date » plutot
-- qu'en « timestamp with time zone », c'est normal — le lecteur de
-- l'application sait desormais lire les deux formats.
