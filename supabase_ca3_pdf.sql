-- =====================================================================
--  RevisionVEB — pièces des déclarations de TVA
--  À exécuter dans Supabase Studio → SQL Editor. Idempotent.
--
--  Le PDF de chaque CA3 importée était analysé puis perdu. Il est désormais
--  conservé et déposé sur Storage, comme les autres pièces justificatives ;
--  ces deux colonnes portent son nom et son chemin.
-- =====================================================================

alter table public.ca3_periods
  add column if not exists doc_name text not null default '',
  add column if not exists doc_path text not null default '';
