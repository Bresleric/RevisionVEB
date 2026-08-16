#!/bin/bash
# Commit et push des correctifs de synchronisation et de SIG.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-sync-dates-et-sig.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): lecture des dates et arbitrage des factures dimmobilisation

Dates remplacees par la date du jour
- une colonne Postgres de type date renvoie 2025-10-08, sans heure
- ISO8601DateFormatter par defaut exige lheure et echouait en silence
- lappelant retombait sur la valeur locale, soit la date du jour pour une
  ligne fraichement creee : les dates de facture etaient remplacees par la
  date de synchronisation
- le lecteur accepte desormais date seule, horodatage ISO avec ou sans
  fraction de seconde, et horodatage Postgres sans T

Factures dimmobilisation qui secrasaient entre les deux Macs
- ImmoInvoice ne portait aucune date de modification : chaque machine
  ecrasait la version de lautre, la derniere synchronisee gagnait
- ajout de updatedAt (migration additive) et horodatage a chaque saisie
- la lecture ne remplace plus une saisie locale par une version distante
  plus ancienne

Soldes intermediaires de gestion
- colonne N-2 recalculee dans laffichage hors du moteur : signe des ventes
  non inverse, et compte 606 compte deux fois dans les matieres
- elle applique desormais les memes regles que les colonnes N et N-1
- diagnostic des frais de personnel : total N et N-1, nombre de comptes 64x,
  detection des comptes en double avec leur fichier source
- signalement des comptes de classe 6 absents de tous les postes du SIG
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :  cd ~/Developer/RevisionVEB && git pull --ff-only"
