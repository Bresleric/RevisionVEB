#!/bin/bash
# Commit et push : lenvoi respecte lhorodatage distant.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-envoi-respecte-horodatage.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): lenvoi ecrasait les donnees plus recentes de lautre Mac

Constat mesure
- le MacBook Air envoie bien ses modifications : trois lignes horodatees
  08:46, 08:47 et 10:23, dont une designation saisie a la main
- le Mac Mini les ecrase a son demarrage en poussant ses propres lignes,
  toutes horodatees 07:33:07

Cause
- larbitrage par date de derniere modification nexistait quau
  chargement, jamais a lecriture
- lenvoi ecrasait sans condition : la derniere machine a demarrer
  imposait ses valeurs, meme plus anciennes
- un Mac au repos annulait donc le travail de lautre en souvrant

Correction
- push accepte un bloc horodatage ; quand il est fourni, les dates
  distantes sont relevees avant lenvoi et une ligne plus recente sur
  Supabase nest pas ecrasee
- elle sera adoptee au chargement qui suit, comme prevu
- applique aux factures dimmobilisation, les seules a porter aujourdhui
  une date de modification exploitable

Fermeture
- delai porte de 20 a 45 s : linventaire des pieces justificatives sur le
  bucket prend a lui seul une dizaine de secondes, et vingt secondes
  coupaient systematiquement lenvoi en cours
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
