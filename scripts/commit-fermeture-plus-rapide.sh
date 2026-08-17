#!/bin/bash
# Commit et push : fermeture plus rapide, sans inventaire des pieces.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-fermeture-plus-rapide.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
perf(sync): fermeture plus rapide, sans inventaire des pieces

Le delai de 45 s etait atteint a chaque fermeture. Le coupable est
linventaire des pieces justificatives sur le bucket : une dizaine de
secondes pour une quarantaine de fichiers.

Cet inventaire na pas sa place a la fermeture — chaque piece est deja
versee au moment ou elle est rattachee. Le rattrapage reste assure au
demarrage et a lenvoi periodique.

- pousserTout accepte avecPieces
- envoiFinal passe avecPieces: false
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
