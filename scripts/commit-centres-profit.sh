#!/bin/bash
# Commit et push : centres de profit + PDF du detail dun compte.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-centres-profit.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(cycle A): soldes intermediaires par centre de profit

Le compte de resultat consolide dit ce que gagne la societe, pas lequel
des deux restaurants la porte. Trois onglets repondent a cela.

Par centre de profit
- la cascade complete des SIG en quatre colonnes : Freddy, Liesel,
  Dirigeants, Total
- les charges communes se repartissent selon leur cle
- les comptes de remuneration des dirigeants restent a part : ils ne sont
  imputables a aucun restaurant
- un compte de classe 6 ou 7 sans rattachement nest impute nulle part, et
  un bandeau le signale avec son montant. Laffecter arbitrairement
  donnerait un total credible mais faux

Evolution
- une colonne par exercice, avec la variation du dernier sur le precedent
- selecteur Freddy, Liesel, Dirigeants ou Ensemble
- la couleur de la variation suit le sens reel et non le signe : une
  hausse est favorable sur un solde ou un produit, defavorable sur une
  charge. Seul ce dont le sens est sur est colore

Parametrage
- rattachement de chaque compte, avec sa cle quand il est commun
- le rattachement vaut pour le dossier et non pour un exercice : cest ce
  qui rend la comparaison pluriannuelle possible, et il survit aux
  reimports de balance
- cle deduite du chiffre daffaires, affichee et applicable en un clic aux
  charges communes. Elle se calcule sur les seules ventes directement
  rattachees : inclure les ventes communes la rendrait circulaire
- import CSV de la table de correspondance depuis le module Import

Boucle de synchronisation complete : modele, table Supabase avec policy,
envoi avec arbitrage par horodatage, chargement.

Disposition
- GeometryReader sur lecran de parametrage : sans lui la pile reclamait
  plus de hauteur que la fenetre, le sommet de la vue remontait sous la
  barre de titre et le selecteur donglets devenait inatteignable
- taille de fenetre par defaut, la fenetre se dimensionnant sinon sur la
  hauteur ideale de son contenu

PDF du detail dun compte
- bouton PDF dans la feuille de detail, format paysage
- en-tete, bandeau de synthese, pagination, total sur la derniere page
- une ligne sans piece saffiche absente : cest le premier point que
  relevera lexpert-comptable
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
