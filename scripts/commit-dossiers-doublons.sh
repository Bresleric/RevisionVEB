#!/bin/bash
# Commit et push du nettoyage des dossiers en double.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-dossiers-doublons.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): dossiers en double entre les deux Macs

Cause
- seedIfNeeded creait PLANB SARL et Moulin Neuf SARL avec des identifiants
  tires au hasard
- un Mac demarrant sur une base vide fabriquait donc ses propres dossiers,
  que la synchronisation additionnait au lieu de les reconnaitre
- meme defaut que celui des comptes de balance : une identite tiree du
  hasard au lieu de la cle logique

Corrections
- lidentifiant des dossiers de depart derive de leur nom : les deux Macs
  produisent exactement le meme
- dedoublonnage au demarrage, local et distant, des exemplaires homonymes
- prudence : seuls les exemplaires sans aucun exercice sont supprimes. Si
  les deux portent du travail, aucune suppression et un avertissement, la
  fusion demandant de repointer les exercices a la main

Diagnostic des soldes intermediaires
- controle des frais de personnel : total N et N-1, nombre de comptes 64x
- detection des comptes 64x en double, avec leur fichier source
- signalement des comptes de classe 6 absents de tous les postes du SIG
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :  cd ~/Developer/RevisionVEB && git pull --ff-only"
