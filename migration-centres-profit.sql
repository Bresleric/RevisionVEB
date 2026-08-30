-- RevisionVEB — rattachement des comptes aux centres de profit
--
-- A executer dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- Idempotent : peut etre relance sans risque.
--
-- Sans policy RLS, la table bloquerait a la fois les ecritures et les
-- lectures, ces dernieres revenant vides sans le moindre message d'erreur.

CREATE TABLE IF NOT EXISTS centre_profit_rules (
    id             UUID PRIMARY KEY,
    dossier_id     UUID NOT NULL,
    account_number TEXT NOT NULL DEFAULT '',
    -- F (Freddy), L (Liesel), C (commun, reparti), DIR (dirigeants)
    centre_raw     TEXT NOT NULL DEFAULT 'C',
    -- Pourcentage revenant a Liesel quand le compte est commun.
    part_liesel    DOUBLE PRECISION NOT NULL DEFAULT 16.67,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT '1970-01-01T00:00:00Z'
);

-- Un compte, un rattachement, par dossier.
CREATE UNIQUE INDEX IF NOT EXISTS centre_profit_rules_dossier_compte_key
    ON centre_profit_rules (dossier_id, account_number);

ALTER TABLE centre_profit_rules ENABLE ROW LEVEL SECURITY;

-- CREATE POLICY IF NOT EXISTS n'existe pas en Postgres : on supprime puis cree.
DROP POLICY IF EXISTS centre_profit_rules_anon_all ON centre_profit_rules;
CREATE POLICY centre_profit_rules_anon_all ON centre_profit_rules
    AS PERMISSIVE FOR ALL TO anon
    USING (true) WITH CHECK (true);

-- Verification : doit renvoyer une ligne.
SELECT tablename, policyname FROM pg_policies
WHERE tablename = 'centre_profit_rules';
