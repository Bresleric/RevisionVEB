#!/bin/bash
# Commit et push : rechargement integral au demarrage, sans envoi prealable.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-rechargement-au-demarrage.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
fix(sync): une machine divergente reecrivait Supabase avant tout clic

Constat
- les six factures sur Supabase portaient toutes le meme updated_at,
  linstant de migration du MacBook Air, avec ses dates de 2026
- le Mac Mini navait jamais rien pousse depuis

Cause reelle
- la synchronisation demarre avec lapplication et pousse AVANT de charger
- une machine divergente reecrivait donc ses valeurs sur Supabase avant
  quon ait pu cliquer quoi que ce soit
- le bouton Recharger depuis Supabase rapatriait ensuite ce quelle venait
  elle-meme dy ecrire : aucun bouton ne pouvait gagner cette course

Correction
- le rechargement integral devient un drapeau lu AVANT tout envoi
- Reglages : le bouton programme loperation, elle prend effet au
  redemarrage de lapplication
- au demarrage suivant, la machine nenvoie rien, vide son cache et adopte
  Supabase tel quel, puis le drapeau se desarme

Note
- la valeur par defaut Date.distantPast posee au commit precedent ne
  corrige pas les lignes deja migrees : elles portent une valeur figee.
  Cest le rechargement qui les remet daplomb.
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
