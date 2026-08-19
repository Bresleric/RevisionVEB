#!/bin/bash
# Commit et push : doublons de TVA + arbitrage par horodatage (vague 1).
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-doublons-tva.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(tva): declarations comptees en double apres reimport

Cause
- Ca3Entry portait un identifiant tire au hasard
- limport supprime bien les lignes locales de la periode avant de
  reinserer, mais rien ne supprimait les anciennes sur Supabase
- elles redescendaient au chargement suivant : la periode portait deux
  jeux de lignes, base et TVA collectee comptees double
- les periodes ca3_periods netaient pas concernees, leur identifiant
  derivant deja de exercice et periode

Corrections
- identifiant derive de exercice, periode, taux : une declaration ne porte
  quune ligne par taux, la cle est naturelle
- envoi resolu sur cette cle logique, sinon lindex unique rejette
  lecriture en 23505 au lieu de mettre a jour
- dedoublonnage local et distant au demarrage et apres chargement, sinon
  la machine qui porte encore les doublons les repousse avant de charger

Arbitrage par horodatage, vague 1
- lenvoi respecte desormais la date distante pour les justifications de
  compte, les controles de revision, les rapprochements bancaires et le
  detail des comptes
- ReconItem gagne updatedAt, avec touch() a chaque point de saisie : un
  champ modifiable sans horodatage serait perpetuellement perdant
- valeur par defaut distantPast : une ligne jamais editee ne revendique
  aucune autorite ; une ligne creee porte la date du jour
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
