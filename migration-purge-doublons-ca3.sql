-- RevisionVEB — purge des lignes de TVA en double
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- A LANCER SECTION PAR SECTION : l'editeur n'affiche que le dernier resultat.
--
-- CAUSE : Ca3Entry portait un identifiant tire au hasard. Un reimport
-- supprimait les lignes locales et en creait de nouvelles, mais rien ne
-- supprimait les anciennes sur Supabase : elles redescendaient au chargement
-- suivant et la periode etait comptee deux fois, base et TVA comprises.

-- ===========================================================================
-- SECTION 1 — ETAT DES LIEUX. A lire avant toute suppression.
-- ===========================================================================
SELECT
    count(*)                                             AS lignes_totales,
    count(DISTINCT (exercice_id, periode, taux))         AS lignes_uniques,
    count(*) - count(DISTINCT (exercice_id, periode, taux)) AS doublons
FROM ca3_entries;


-- ===========================================================================
-- SECTION 2 — CONTROLE DE PRUDENCE, a lancer seul.
--
-- Les exemplaires d'une meme ligne portent-ils des montants DIFFERENTS ?
-- Si cette requete ne renvoie rien : les doublons sont de simples copies, la
-- purge est sans risque.
-- Si elle renvoie des lignes : ces periodes ont ete importees avec des
-- valeurs divergentes. NE PAS PURGER en aveugle — reimporter les
-- declarations concernees depuis leurs PDF, qui font foi.
-- ===========================================================================
SELECT
    periode,
    taux,
    count(*)                       AS exemplaires,
    round(min(base)::numeric, 2)   AS base_min,
    round(max(base)::numeric, 2)   AS base_max,
    round(min(tva)::numeric, 2)    AS tva_min,
    round(max(tva)::numeric, 2)    AS tva_max
FROM ca3_entries
GROUP BY exercice_id, periode, taux
HAVING count(*) > 1
   AND (max(base) - min(base) > 0.005 OR max(tva) - min(tva) > 0.005)
ORDER BY periode, taux;


-- ===========================================================================
-- SECTION 3 — PURGE. A lancer seulement si la section 2 ne renvoie rien.
--
-- Conserve une ligne par (exercice, periode, taux) : la plus grande par
-- identifiant, pour que le resultat soit le meme quelle que soit la machine
-- qui execute.
-- ===========================================================================
DELETE FROM ca3_entries a
USING ca3_entries b
WHERE a.exercice_id = b.exercice_id
  AND a.periode     = b.periode
  AND a.taux        = b.taux
  AND a.id          < b.id;


-- ===========================================================================
-- SECTION 4 — GARDE-FOU. Une declaration, une ligne par taux.
-- Desormais un reimport met a jour au lieu d'empiler.
-- ===========================================================================
CREATE UNIQUE INDEX IF NOT EXISTS ca3_entries_exercice_periode_taux_key
    ON ca3_entries (exercice_id, periode, taux);


-- ===========================================================================
-- SECTION 5 — VERIFICATION. doublons doit valoir 0.
-- ===========================================================================
SELECT
    count(*)                                             AS lignes_totales,
    count(*) - count(DISTINCT (exercice_id, periode, taux)) AS doublons
FROM ca3_entries;
