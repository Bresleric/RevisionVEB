#!/bin/bash
# Commit et push : nettoyage apres chargement.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-nettoyage-apres-chargement.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): nettoyer apres le chargement, pas seulement avant

Symptome
- les comptes dun import perime revenaient a chaque demarrage
- les soldes intermediaires refaussaient meme apres nettoyage et rebuild

Cause
- le dedoublonnage tournait au debut de la synchronisation, avant lenvoi
- or les comptes obsoletes arrivent a la fin, au chargement
- ils traversaient donc toute la session et les soldes intermediaires se
  calculaient dessus ; le nettoyage ne prenait effet quau demarrage suivant

Correction
- etape 3 de nettoyage apres le chargement : balance et assiettes DSN
- suppression a distance aussi, pas seulement en local. La decision est
  fiable a ce moment precis, le jeu local reflechissant lintegralite de la
  table distante puisquil vient den etre charge
- les comptes obsoletes disparaissent donc definitivement de Supabase au
  lieu de redescendre a chaque synchronisation
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
