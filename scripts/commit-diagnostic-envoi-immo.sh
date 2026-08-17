#!/bin/bash
# Commit et push : diagnostic de lenvoi des factures immo.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-diagnostic-envoi-immo.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
chore(sync): tracer ce qui est reellement envoye pour les factures immo

Pendant deux jours, le diagnostic sest fait par deduction : le Mac Mini
affichait 45 600, Supabase contenait 38 877, et je supposais tour a tour
un probleme didentifiants, dhorodatage ou darbitrage. Toutes ces
hypotheses etaient fausses.

Une seule mesure a tranche : imprimer les identifiants et montants
reellement transmis, puis les confronter au contenu de la table. Les deux
listes correspondaient ligne pour ligne — lenvoi fonctionnait, et le
probleme etait ailleurs, dans lordre des operations au demarrage.

- six lignes imprimees avant lenvoi : identifiant court, libelle, montant,
  date de derniere modification
- cout negligeable, et cest la seule fenetre sur ce qui part reellement

Ajoute aussi verification-donnees-supabase.sql : controle du contenu de
Supabase apres synchronisation, en lecture seule.
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse."
