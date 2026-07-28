-- =====================================================================
--  RevisionVEB — mise à niveau du schéma Supabase
--  À exécuter une fois dans Supabase Studio → SQL Editor.
--
--  Les tables existaient déjà mais étaient incomplètes : seules quelques
--  colonnes avaient été créées, ce qui empêchait toute synchronisation.
--  Ce script est idempotent : on peut le relancer sans risque.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Nouvelle table : points en suspens (commentaires et tâches par cycle)
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
-- 2. Colonnes manquantes sur les tables existantes
-- ---------------------------------------------------------------------

-- Contrôles de révision + notes de synthèse
alter table public.control_states
  add column if not exists item_id    text not null default '',
  add column if not exists statut_raw text not null default 'À faire',
  add column if not exists note       text not null default '';

-- Justifications de comptes
alter table public.account_justifications
  add column if not exists account_number text not null default '',
  add column if not exists solde_justifie double precision,
  add column if not exists doc_name       text not null default '',
  add column if not exists doc_path       text not null default '',
  add column if not exists note           text not null default '';

-- Taux de TVA par compte
alter table public.tva_compte_taux
  add column if not exists taux text not null default '';

-- Rapprochements bancaires
alter table public.bank_reconciliations
  add column if not exists account_number text not null default '',
  add column if not exists solde_extrait  double precision,
  add column if not exists note           text not null default '';

-- Éléments de rapprochement
alter table public.recon_items
  add column if not exists account_number text not null default '',
  add column if not exists ordre          integer not null default 0,
  add column if not exists doc_name       text not null default '',
  add column if not exists doc_path       text not null default '';

-- Déclarations de TVA : lignes
alter table public.ca3_entries
  add column if not exists ordre integer not null default 0;

-- Déclarations de TVA : périodes
alter table public.ca3_periods
  add column if not exists tva_deductible double precision not null default 0,
  add column if not exists credit_m1      double precision not null default 0,
  add column if not exists ca_ht          double precision not null default 0,
  add column if not exists ligne16        double precision not null default 0,
  add column if not exists ligne19        double precision not null default 0,
  add column if not exists ligne20        double precision not null default 0;

-- Factures d'investissement
alter table public.immo_invoices
  add column if not exists date        timestamptz not null default now(),
  add column if not exists compte      text not null default '',
  add column if not exists designation text not null default '',
  add column if not exists montant     double precision not null default 0,
  add column if not exists doc_name    text not null default '',
  add column if not exists doc_path    text not null default '',
  add column if not exists ordre       integer not null default 0;

-- Immobilisations
alter table public.immo_assets
  add column if not exists ordre integer not null default 0;

-- Mouvements de classe 2
alter table public.class2_movements
  add column if not exists date       timestamptz not null default now(),
  add column if not exists complement text not null default '',
  add column if not exists debit      double precision not null default 0,
  add column if not exists credit     double precision not null default 0,
  add column if not exists ordre      integer not null default 0;

-- ---------------------------------------------------------------------
-- 3. Row Level Security : accès complet via la clé publishable
--    (même politique que dossiers / exercices / balance_accounts)
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
-- 4. Index de recherche par exercice
-- ---------------------------------------------------------------------
create index if not exists control_states_exercice_idx        on public.control_states (exercice_id);
create index if not exists account_justifications_exercice_idx on public.account_justifications (exercice_id);
create index if not exists bank_reconciliations_exercice_idx  on public.bank_reconciliations (exercice_id);
create index if not exists recon_items_exercice_idx           on public.recon_items (exercice_id);
create index if not exists ca3_entries_exercice_idx           on public.ca3_entries (exercice_id);
create index if not exists ca3_periods_exercice_idx           on public.ca3_periods (exercice_id);
create index if not exists immo_invoices_exercice_idx         on public.immo_invoices (exercice_id);
create index if not exists immo_assets_exercice_idx           on public.immo_assets (exercice_id);
create index if not exists class2_movements_exercice_idx      on public.class2_movements (exercice_id);
create index if not exists tva_compte_taux_exercice_idx       on public.tva_compte_taux (exercice_id);
create index if not exists account_cycle_rules_dossier_idx    on public.account_cycle_rules (dossier_id);
