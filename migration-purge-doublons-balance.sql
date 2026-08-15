-- RevisionVEB — purge des doublons de balance_accounts
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
--
-- CAUSE : jusqu'ici, chaque import creait des lignes avec de nouveaux
-- identifiants sans supprimer les precedentes. La table a donc accumule une
-- generation de lignes par import, et les comptes revenaient en autant
-- d'exemplaires sur l'autre Mac.
--
-- Ce script garde UNE ligne par (exercice, compte) — la plus recemment
-- importee — supprime les autres, et pose une contrainte d'unicite pour que le
-- probleme ne puisse plus se reproduire.
--
-- A executer AVANT de relancer l'application sur les deux Macs.

-- 1. Etat des lieux (a lire avant de supprimer).
SELECT
    count(*)                                              AS lignes_totales,
    count(DISTINCT (exercice_id, account_number))         AS comptes_uniques,
    count(*) - count(DISTINCT (exercice_id, account_number)) AS doublons_a_supprimer
FROM balance_accounts;

-- 2. Suppression des doublons : on conserve la ligne dont import_date est la
--    plus recente ; a egalite, le plus grand identifiant, pour que le resultat
--    soit le meme quel que soit le Mac qui execute.
DELETE FROM balance_accounts a
USING balance_accounts b
WHERE a.exercice_id = b.exercice_id
  AND a.account_number = b.account_number
  AND (a.import_date, a.id) < (b.import_date, b.id);

-- 3. Contrainte d'unicite : un compte, un exercice, une ligne.
--    Desormais un reimport met a jour au lieu d'empiler.
CREATE UNIQUE INDEX IF NOT EXISTS balance_accounts_exercice_compte_key
    ON balance_accounts (exercice_id, account_number);

-- 4. Verification : doublons_restants doit valoir 0.
SELECT
    count(*)                                              AS lignes_totales,
    count(*) - count(DISTINCT (exercice_id, account_number)) AS doublons_restants
FROM balance_accounts;
