-- =====================================================================
--  RevisionVEB — schéma Supabase
--  À exécuter dans Supabase Studio → SQL Editor. Idempotent.
--
--  Historique : les tables du travail d'audit existaient déjà, créées avec
--  un jeu de noms de colonnes (file_name, status_raw, compte_51, taux_raw…).
--  Une première version de ce script a ajouté des colonnes parallèles
--  (doc_name, statut_raw, account_number, taux…) au lieu de réutiliser
--  l'existant. L'application s'aligne désormais sur les colonnes d'origine ;
--  la section 3 retire les doublons devenus inutiles.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Points en suspens : commentaires et tâches par cycle
-- ---------------------------------------------------------------------
create table if not exists public.points_en_suspens (
  id           uuid primary key,
  exercice_id  uuid        not null,
  cycle_raw    text        not null,
  titre        text        not null default '',
  detail       text        not null default '',
  type_raw     text        not null default 'Commentaire',
  statut_raw   text        not null default 'Ouvert',
  priorite_raw text        not null default 'Normale',
  responsable  text        not null default '',
  echeance     timestamptz,
  cree_le      timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists points_en_suspens_exercice_cycle_idx
  on public.points_en_suspens (exercice_id, cycle_raw);

-- ---------------------------------------------------------------------
-- 2. Colonnes réellement manquantes
-- ---------------------------------------------------------------------

-- Identifiant de l'élément de contrôle dans le catalogue du cycle
alter table public.control_states
  add column if not exists item_id text not null default '';

-- Solde justifié saisi par le réviseur
alter table public.account_justifications
  add column if not exists solde_justifie double precision;

-- Note libre sur le rapprochement
alter table public.bank_reconciliations
  add column if not exists note text not null default '';

-- Ordre d'affichage et pièce jointe des éléments de rapprochement
alter table public.recon_items
  add column if not exists account_number text not null default '',
  add column if not exists ordre          integer not null default 0,
  add column if not exists doc_name       text not null default '',
  add column if not exists doc_path       text not null default '';

alter table public.ca3_entries
  add column if not exists ordre integer not null default 0;

alter table public.ca3_periods
  add column if not exists tva_deductible double precision not null default 0,
  add column if not exists credit_m1      double precision not null default 0,
  add column if not exists ca_ht          double precision not null default 0,
  add column if not exists ligne16        double precision not null default 0,
  add column if not exists ligne19        double precision not null default 0,
  add column if not exists ligne20        double precision not null default 0;

alter table public.immo_invoices
  add column if not exists date        timestamptz not null default now(),
  add column if not exists compte      text not null default '',
  add column if not exists designation text not null default '',
  add column if not exists montant     double precision not null default 0,
  add column if not exists doc_name    text not null default '',
  add column if not exists doc_path    text not null default '',
  add column if not exists ordre       integer not null default 0;

alter table public.immo_assets
  add column if not exists ordre integer not null default 0;

alter table public.class2_movements
  add column if not exists date       timestamptz not null default now(),
  add column if not exists complement text not null default '',
  add column if not exists debit      double precision not null default 0,
  add column if not exists credit     double precision not null default 0,
  add column if not exists ordre      integer not null default 0;

-- ---------------------------------------------------------------------
-- 3. Retrait des colonnes en double
--
--    Ces colonnes avaient été ajoutées à tort en doublon de colonnes
--    existantes. Elles n'ont jamais reçu de données : toutes les écritures
--    échouaient sur les contraintes NOT NULL des colonnes d'origine.
--    L'application utilise désormais les colonnes d'origine.
-- ---------------------------------------------------------------------
alter table public.account_justifications
  drop column if exists doc_name,        -- doublon de file_name
  drop column if exists doc_path,        -- doublon de file_path
  drop column if exists note;            -- doublon de notes

alter table public.control_states
  drop column if exists statut_raw,      -- doublon de status_raw
  drop column if exists note;            -- doublon de notes

alter table public.bank_reconciliations
  drop column if exists account_number,  -- doublon de compte_51
  drop column if exists solde_extrait;   -- doublon de solde_banque

alter table public.tva_compte_taux
  drop column if exists taux;            -- doublon de taux_raw

-- ---------------------------------------------------------------------
-- 4. Contraintes héritées inutilisées par l'application
--
--    Ces colonnes proviennent d'un modèle antérieur. L'application ne les
--    renseigne pas : on lève le NOT NULL pour ne pas bloquer les écritures.
-- ---------------------------------------------------------------------
alter table public.recon_items          alter column date_operation drop not null;
alter table public.bank_reconciliations alter column solde_compta   drop not null;
alter table public.immo_invoices        alter column numero         drop not null;
alter table public.immo_invoices        alter column fournisseur    drop not null;
alter table public.immo_invoices        alter column date_facture   drop not null;
alter table public.immo_invoices        alter column montant_ht     drop not null;
alter table public.class2_movements     alter column montant        drop not null;
alter table public.class2_movements     alter column date_operation drop not null;
alter table public.ca3_periods          alter column date_debut     drop not null;
alter table public.ca3_periods          alter column date_fin       drop not null;

-- ---------------------------------------------------------------------
-- 5. Row Level Security : accès complet via la clé publishable
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'points_en_suspens', 'control_states', 'account_justifications',
    'tva_compte_taux', 'bank_reconciliations', 'recon_items',
    'ca3_entries', 'ca3_periods', 'immo_invoices', 'immo_assets',
    'class2_movements', 'account_cycle_rules', 'soldes_intermediares'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_all', t);
    execute format(
      'create policy %I on public.%I for all using (true) with check (true)',
      t || '_all', t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. Index de recherche par exercice
-- ---------------------------------------------------------------------
create index if not exists control_states_exercice_idx         on public.control_states (exercice_id);
create index if not exists account_justifications_exercice_idx on public.account_justifications (exercice_id);
create index if not exists bank_reconciliations_exercice_idx   on public.bank_reconciliations (exercice_id);
create index if not exists recon_items_exercice_idx            on public.recon_items (exercice_id);
create index if not exists ca3_entries_exercice_idx            on public.ca3_entries (exercice_id);
create index if not exists ca3_periods_exercice_idx            on public.ca3_periods (exercice_id);
create index if not exists immo_invoices_exercice_idx          on public.immo_invoices (exercice_id);
create index if not exists immo_assets_exercice_idx            on public.immo_assets (exercice_id);
create index if not exists class2_movements_exercice_idx       on public.class2_movements (exercice_id);
create index if not exists tva_compte_taux_exercice_idx        on public.tva_compte_taux (exercice_id);
create index if not exists account_cycle_rules_dossier_idx     on public.account_cycle_rules (dossier_id);
