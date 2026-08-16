-- RevisionVEB — etat des lieux des dossiers et exercices en double
--
-- A coller dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- NE MODIFIE RIEN : ce script ne fait que lire.
--
-- Chaque Mac demarrant sur une base vide creait ses propres dossiers avec des
-- identifiants aleatoires. Les deux jeux coexistent donc, et les saisies sont
-- potentiellement reparties entre eux. Avant toute fusion, il faut savoir
-- lequel porte quoi.

-- 1. Les dossiers, avec le volume rattache a chacun.
SELECT
    d.id,
    d.nom,
    d.ordre,
    (SELECT count(*) FROM exercices e WHERE e.dossier_id = d.id) AS exercices,
    (SELECT count(*) FROM balance_accounts b
       WHERE b.exercice_id IN (SELECT id FROM exercices e WHERE e.dossier_id = d.id)) AS comptes
FROM dossiers d
ORDER BY d.nom, d.ordre;

-- 2. Les exercices, avec ce qui y est reellement saisi.
--    C'est ce tableau qui dit lequel garder : celui qui porte le travail.
SELECT
    e.id,
    d.nom                AS dossier,
    e.libelle            AS exercice,
    e.date_cloture,
    (SELECT count(*) FROM balance_accounts b WHERE b.exercice_id = e.id) AS comptes,
    (SELECT count(*) FROM account_justifications j WHERE j.exercice_id = e.id) AS justifications,
    (SELECT count(*) FROM recon_items r WHERE r.exercice_id = e.id)      AS lignes_detail,
    (SELECT count(*) FROM immo_invoices i WHERE i.exercice_id = e.id)    AS factures_immo,
    (SELECT count(*) FROM ca3_entries c WHERE c.exercice_id = e.id)      AS lignes_tva,
    (SELECT count(*) FROM points_en_suspens p WHERE p.exercice_id = e.id) AS points_suspens
FROM exercices e
JOIN dossiers d ON d.id = e.dossier_id
ORDER BY d.nom, e.libelle;

-- 3. Dossiers portant le meme nom : les candidats a la fusion.
SELECT nom, count(*) AS exemplaires, array_agg(id) AS identifiants
FROM dossiers
GROUP BY nom
HAVING count(*) > 1;
