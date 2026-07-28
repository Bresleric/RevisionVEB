-- =====================================================================
--  RevisionVEB — dépôt des pièces justificatives
--  À exécuter dans Supabase Studio → SQL Editor. Idempotent.
--
--  La base ne transporte que le chemin local du document, propre au Mac qui
--  a rattaché la pièce. Le fichier lui-même passe désormais par Storage, ce
--  qui rend les cross-références ouvrables depuis les deux machines.
--
--  Chemin d'un objet : <exercice_id>/<nom du fichier>
-- =====================================================================

-- Bucket privé : les pièces comptables ne doivent pas être accessibles
-- publiquement par URL.
insert into storage.buckets (id, name, public)
values ('justificatifs', 'justificatifs', false)
on conflict (id) do nothing;

-- Accès complet via la clé publishable, restreint à ce seul bucket.
drop policy if exists "justificatifs_read"   on storage.objects;
drop policy if exists "justificatifs_write"  on storage.objects;
drop policy if exists "justificatifs_update" on storage.objects;
drop policy if exists "justificatifs_delete" on storage.objects;

create policy "justificatifs_read" on storage.objects
  for select using (bucket_id = 'justificatifs');

create policy "justificatifs_write" on storage.objects
  for insert with check (bucket_id = 'justificatifs');

create policy "justificatifs_update" on storage.objects
  for update using (bucket_id = 'justificatifs')
            with check (bucket_id = 'justificatifs');

create policy "justificatifs_delete" on storage.objects
  for delete using (bucket_id = 'justificatifs');
