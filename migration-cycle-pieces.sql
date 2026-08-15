-- RevisionVEB — pièces justificatives rattachées à un cycle de révision
--
-- À exécuter dans Supabase → SQL Editor du projet qhvtqapasxekkumuztak.
-- Idempotent : peut être relancé sans risque.
--
-- Sans la policy RLS, la table bloquerait à la fois les écritures
-- (« new row violates row-level security policy ») et les lectures, qui
-- reviendraient vides sans message d'erreur.

CREATE TABLE IF NOT EXISTS cycle_pieces (
    id             UUID PRIMARY KEY,
    exercice_id    UUID NOT NULL,
    cycle_raw      TEXT NOT NULL DEFAULT '',
    categorie      TEXT NOT NULL DEFAULT '',
    libelle        TEXT NOT NULL DEFAULT '',
    mois           INTEGER NOT NULL DEFAULT 0,
    annee          INTEGER NOT NULL DEFAULT 0,
    etablissement  TEXT NOT NULL DEFAULT '',
    doc_name       TEXT NOT NULL DEFAULT '',
    doc_path       TEXT NOT NULL DEFAULT '',
    note           TEXT NOT NULL DEFAULT '',
    ordre          INTEGER NOT NULL DEFAULT 0,
    ajoute_le      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cycle_pieces_exercice_idx
    ON cycle_pieces (exercice_id, cycle_raw);

ALTER TABLE cycle_pieces ENABLE ROW LEVEL SECURITY;

-- CREATE POLICY IF NOT EXISTS n'existe pas en Postgres : on supprime puis on crée.
DROP POLICY IF EXISTS cycle_pieces_anon_all ON cycle_pieces;
CREATE POLICY cycle_pieces_anon_all ON cycle_pieces
    AS PERMISSIVE FOR ALL TO anon
    USING (true) WITH CHECK (true);

-- Vérification : doit renvoyer une ligne.
SELECT tablename, policyname FROM pg_policies WHERE tablename = 'cycle_pieces';
