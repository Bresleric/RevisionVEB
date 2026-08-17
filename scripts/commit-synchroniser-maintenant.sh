#!/bin/bash
# Commit et push : bouton Synchroniser maintenant.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-synchroniser-maintenant.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(sync): bouton Synchroniser maintenant

Symptome
- des saisies faites sur le MacBook Air ne remontaient pas, alors que la
  synchronisation venait detre reparee

Cause
- fullSync ne sexecute quau lancement de lapplication, et rien ne part a
  la fermeture : une saisie ne quittait la machine quau demarrage suivant
- pire encore apres un rechargement integral, qui consomme le lancement
  sans rien envoyer : les saisies de cette session-la navaient aucune
  chance de partir
- lutilisateur qui saisit puis quitte croit legitimement avoir
  synchronise, alors que son travail reste local

Correction
- fullSync accepte force: true pour relancer une synchronisation deja
  faite dans la session
- Reglages : bouton Synchroniser maintenant, avec lheure du dernier envoi
- rappel explicite : a faire avant de quitter, sinon le travail ne part
  quau prochain demarrage
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
