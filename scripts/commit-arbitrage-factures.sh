#!/bin/bash
# Commit et push : arbitrage des factures immo entre les deux Macs.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-arbitrage-factures.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): les factures immo ne convergeaient jamais

Cause
- updatedAt avait Date() comme valeur par defaut dans la declaration
- or cest cette valeur quheritent les lignes existantes a la migration du
  schema : une ligne jamais retouchee se pretendait fraichement modifiee
- les deux Macs se declaraient donc tous deux les plus recents, aucun ne
  cedait, et les deux listes restaient divergentes indefiniment

Correction
- valeur par defaut Date.distantPast : une ligne jamais editee ne
  revendique aucune autorite
- seule une saisie reelle, ou le bouton Faire de cette liste la reference,
  donne le dernier mot
- diagnostic au chargement : chaque facture divergente conservee en local
  est nommee, avec les deux montants et les deux horodatages

Nettoyage apres chargement
- etape 3 de la synchronisation : balance et assiettes DSN
- le dedoublonnage tournait avant lenvoi alors que les comptes obsoletes
  arrivent au chargement ; ils traversaient la session et faussaient les
  soldes intermediaires jusquau demarrage suivant
- suppression a distance aussi, le jeu local reflechissant a cet instant
  lintegralite de la table distante
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
