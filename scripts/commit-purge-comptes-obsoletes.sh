#!/bin/bash
# Commit et push : dossiers en double + purge des comptes obsoletes.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-purge-comptes-obsoletes.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): comptes obsoletes ressuscites par la synchronisation

Symptome
- reimporter la balance corrigeait les soldes intermediaires
- au redemarrage suivant ils redevenaient faux, a lidentique
- les frais de personnel ressortaient a 936 895 au lieu de 875 672,
  soit 61 223 euros portes par trois comptes absents de Cegid

Cause
- importBalance supprime les comptes locaux de lexercice avant de
  reinserer, mais rien ne supprimait les lignes distantes
- un compte solde depuis, disparu du nouvel export comptable, restait
  sur Supabase et redescendait au premier chargement
- le reimport ne pouvait donc jamais gagner

Correction
- purgeBalanceAccountsAbsentes supprime a distance les comptes de
  lexercice absents du dernier import
- appelee uniquement apres un import, seul moment ou le jeu local fait
  autorite pour cet exercice

Dossiers en double
- lidentifiant des dossiers de depart derive de leur nom, les deux Macs
  produisent le meme
- dedoublonnage au demarrage, local et distant, des exemplaires homonymes
- seuls les exemplaires sans aucun exercice sont supprimes ; si les deux
  portent du travail, aucune suppression et un avertissement

Diagnostic des soldes intermediaires
- controle des frais de personnel : total N et N-1, nombre de comptes 64x
- detection des comptes 64x en double avec leur fichier source
- signalement des comptes de classe 6 absents de tous les postes du SIG
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :  cd ~/Developer/RevisionVEB && git pull --ff-only"
