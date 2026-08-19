-- RevisionVEB — les declarations de TVA sont-elles comptees en double ?
--
-- A coller dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- NE MODIFIE RIEN : ce script ne fait que lire.
--
-- Ca3Entry porte un identifiant tire au hasard. Un reimport supprime les
-- lignes locales et en cree de nouvelles, mais rien ne supprime les anciennes
-- sur Supabase : elles redescendent au chargement suivant et la periode est
-- comptee deux fois.
--
-- Les periodes (ca3_periods) ne sont pas concernees : leur identifiant derive
-- de (exercice, periode), un reimport les ecrase proprement.

-- 1. Y a-t-il plusieurs lignes pour un meme (exercice, periode, taux) ?
--    Une declaration ne porte qu'une ligne par taux. Tout exemplaires > 1
--    est un doublon, et la base comme la TVA sont comptees en double.
SELECT
    periode,
    taux,
    count(*)                          AS exemplaires,
    round(sum(base)::numeric, 2)      AS base_cumulee,
    round(sum(tva)::numeric, 2)       AS tva_cumulee,
    round((sum(base) / count(*))::numeric, 2) AS base_reelle,
    round((sum(tva)  / count(*))::numeric, 2) AS tva_reelle
FROM ca3_entries
GROUP BY exercice_id, periode, taux
HAVING count(*) > 1
ORDER BY periode, taux;

-- 2. Vue d'ensemble par periode : nombre de lignes et total declare.
--    Un mois qui porte deux fois plus de lignes que ses voisins est suspect.
SELECT
    periode,
    count(*)                     AS lignes,
    count(DISTINCT taux)         AS taux_distincts,
    round(sum(base)::numeric, 2) AS base_totale,
    round(sum(tva)::numeric, 2)  AS tva_collectee
FROM ca3_entries
GROUP BY exercice_id, periode
ORDER BY periode;

-- 3. Confrontation lignes / periodes : la TVA collectee calculee depuis les
--    lignes doit rester coherente avec la ligne 16 de la declaration.
--    Un ecart proche du double signale le doublon.
SELECT
    p.periode,
    round(p.ligne16::numeric, 2)                     AS ligne16_declaree,
    round(coalesce(sum(e.tva), 0)::numeric, 2)       AS tva_somme_des_lignes,
    round((coalesce(sum(e.tva), 0) - p.ligne16)::numeric, 2) AS ecart
FROM ca3_periods p
LEFT JOIN ca3_entries e
       ON e.exercice_id = p.exercice_id AND e.periode = p.periode
GROUP BY p.exercice_id, p.periode, p.ligne16
ORDER BY p.periode;
