-- RevisionVEB — verification du contenu de Supabase
--
-- A coller dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- NE MODIFIE RIEN : ce script ne fait que lire.
--
-- A executer apres avoir lance le Mac Mini seul, pour verifier que ses
-- donnees sont bien arrivees. Le Mac Mini fait foi.

-- 1. Factures d'investissement (cycle G). Attendu : 6 lignes, total 45 600.
--    La colonne updated_at doit porter l'heure du dernier lancement du
--    Mac Mini, et non celle du MacBook Air.
SELECT
    'FACTURES IMMO'                      AS section,
    to_char(date, 'DD/MM/YYYY')          AS date_facture,
    compte,
    designation,
    montant,
    to_char(updated_at, 'DD/MM HH24:MI') AS modifiee_le
FROM immo_invoices
ORDER BY ordre;

-- 2. Total de controle des factures.
SELECT 'TOTAL FACTURES IMMO' AS section,
       count(*)              AS lignes,
       round(sum(montant)::numeric, 2) AS total_ht
FROM immo_invoices;

-- 3. Detail des comptes de regularisation (cycle D, factures non parvenues).
SELECT
    'DETAIL FNP'   AS section,
    account_number AS compte,
    libelle,
    compte_charge,
    montant_ht,
    taux_tva,
    montant_tva,
    montant        AS ttc,
    doc_name       AS piece
FROM recon_items
ORDER BY account_number, ordre;

-- 4. Volumetrie generale, pour reperer une table anormalement vide.
SELECT 'VOLUMETRIE' AS section, 'balance_accounts' AS table_, count(*) FROM balance_accounts
UNION ALL SELECT 'VOLUMETRIE', 'account_justifications', count(*) FROM account_justifications
UNION ALL SELECT 'VOLUMETRIE', 'recon_items',            count(*) FROM recon_items
UNION ALL SELECT 'VOLUMETRIE', 'immo_invoices',          count(*) FROM immo_invoices
UNION ALL SELECT 'VOLUMETRIE', 'immo_assets',            count(*) FROM immo_assets
UNION ALL SELECT 'VOLUMETRIE', 'ca3_entries',            count(*) FROM ca3_entries
UNION ALL SELECT 'VOLUMETRIE', 'ca3_periods',            count(*) FROM ca3_periods
UNION ALL SELECT 'VOLUMETRIE', 'class2_movements',       count(*) FROM class2_movements
UNION ALL SELECT 'VOLUMETRIE', 'dsn_assiettes',          count(*) FROM dsn_assiettes
UNION ALL SELECT 'VOLUMETRIE', 'cycle_pieces',           count(*) FROM cycle_pieces
UNION ALL SELECT 'VOLUMETRIE', 'points_en_suspens',      count(*) FROM points_en_suspens
ORDER BY 2;
