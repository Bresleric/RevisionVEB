#!/bin/bash
# Commit et push : rechargement integral depuis Supabase.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-recharger-depuis-supabase.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(sync): recharger tout depuis Supabase, sortie de secours de divergence

Quand deux Macs ont diverge, les reconcilier ligne a ligne est vain :
chacun defend sa version et aucun ne cede. Ce bouton tranche autrement.
Il declare Supabase seul depositaire et jette ce que la machine croyait
savoir. Cest le sens du modele affiche au demarrage : source de verite
Supabase, cache local SwiftData.

- Reglages : bouton Recharger tout depuis Supabase, avec confirmation
- nenvoie rien avant deffacer, cest deliberé : pousser dabord
  reintroduirait sur Supabase les valeurs quon cherche a abandonner
- ne touche quaux modeles reellement synchronises. Le grand livre 641 et
  les factures scannees ne le sont pas : les effacer serait une perte
  seche, sans rien pour les restaurer

Arbitrage des factures immo
- updatedAt avait Date() comme valeur par defaut dans la declaration, or
  cest elle quheritent les lignes existantes a la migration du schema
- une ligne jamais retouchee se pretendait donc fraichement modifiee, les
  deux Macs se declaraient les plus recents et aucun ne cedait
- valeur par defaut Date.distantPast : une ligne jamais editee ne
  revendique aucune autorite
- diagnostic au chargement : chaque facture divergente conservee en local
  est nommee, avec les deux montants et les deux horodatages
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
