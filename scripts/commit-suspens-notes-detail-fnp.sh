#!/bin/bash
# Commit et push des travaux du jour sur RevisionVEB.
# A lancer depuis le Mac principal :  bash ~/Developer/RevisionVEB/scripts/commit-suspens-notes-detail-fnp.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(revision): points en suspens par compte, detail ventile des comptes, pieces de cycle

Points en suspens et notes
- deux boutons par compte dans la feuille de chaque cycle, avec compteur des points ouverts
- PendingItem porte desormais le numero de compte (migration additive)
- onglet renomme Suspens / Notes, badge du compte sur chaque carte
- colonne Compte ajoutee a PointsEnSuspens.csv de export expert-comptable

Detail justificatif de nimporte quel compte
- colonne Detail dans la feuille de cycle, ouvrant le detail ligne a ligne
- import multiple de factures : une ligne creee par fichier
- ventilation compte de charge / HT / taux / TVA / TTC pour les comptes de cut-off
- le total detaille devient le solde justifie du compte
- nouvel etat Detail comptes de regularisation.csv dans lexport
- les pieces de detail suivent le cycle du compte au lieu detre toutes classees en B

Pieces rattachees a un cycle
- nouveau modele CyclePiece, avec table Supabase, push et load
- limport DSN archive le PDF au dossier dans le meme geste
- onglet Pieces du cycle H, feuille de travail et recapitulatifs DSN
- bouton justifiant les comptes 641 par la feuille de travail
- dossier Declarations sociales (DSN) dans lexport expert-comptable

Correction des doublons de balance
- identifiant de BalanceAccount derive de (exercice, compte) au lieu detre tire au hasard
- lecture paginee : PostgREST plafonnait les reponses a 1000 lignes
- dedoublonnage par cle logique a la lecture, plus seulement par identifiant

Cycle H
- parser du grand livre 641 et rapprochement mensuel avec les assiettes DSN
- onglets Rapprochement, Ecarts restants, Sources DSN, Detail GL, Methodologie
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :  cd ~/Developer/RevisionVEB && git pull --ff-only"
