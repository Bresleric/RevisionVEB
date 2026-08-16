#!/bin/bash
# Commit et push : la balance comme instantane + arbitrage des factures immo.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-instantane-balance.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): la balance dun exercice est un instantane, pas un cumul

Symptome
- le Mac Mini reimporte la balance, les soldes intermediaires redeviennent
  justes, puis refaussent apres synchronisation
- reimporter ne reglait rien de durable

Cause
- la purge distante ne sexecutait quapres un import, donc sur un seul Mac
- lautre machine gardait les comptes obsoletes dans sa base locale
- la synchronisation poussant AVANT de charger, elle les renvoyait sur
  Supabase avant meme de recevoir la version nettoyee
- les deux machines se les repassaient indefiniment

Correction
- au dedoublonnage, pour chaque exercice, seuls les comptes du dernier
  import sont conserves : deux imports ne se melangent plus
- fenetre de tolerance de 5 minutes, chaque compte portant son propre
  horodatage a quelques millisecondes pres
- le nettoyage a donc lieu sur les deux Macs, sans reimport

Factures dimmobilisation divergentes
- larbitrage se fait sur la date de derniere modification, mais quand
  aucune des deux versions na ete retouchee depuis la migration leurs
  horodatages se valent et personne ne lemporte
- nouveau bouton Faire de cette liste la reference : marque les lignes
  comme les plus recentes pour trancher explicitement
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :  cd ~/Developer/RevisionVEB && git pull --ff-only"
