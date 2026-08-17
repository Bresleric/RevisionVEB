#!/bin/bash
# Commit et push : envoi automatique a la fermeture de lapplication.
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-envoi-a-la-fermeture.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(sync): envoi automatique a la fermeture de lapplication

Symptome
- une saisie faite puis suivie dun simple Cmd-Q ne quittait jamais la
  machine, et lutilisateur croyait legitimement avoir synchronise

Cause
- fullSync ne sexecutait qua louverture, rien ne partait a la fermeture
- pire apres un rechargement integral, qui consomme le lancement sans
  rien envoyer : les saisies de cette session navaient aucune chance

Correction
- AppDelegate.applicationShouldTerminate retient la fermeture avec
  terminateLater, envoie, puis rend la main
- envoiFinal nenvoie que le local vers Supabase, sans chargement en
  retour : recuperer les donnees de lautre Mac au moment de partir na
  aucun interet et doublerait lattente
- delai borne a 20 s : au-dela on rend la main, le reste partira au
  prochain demarrage. Mieux vaut une fermeture qui aboutit quune
  application qui refuse de se fermer
- aucun envoi si un rechargement integral est programme, sinon on
  reintroduirait sur Supabase ce quon veut abandonner

Le bouton Synchroniser maintenant reste disponible dans Reglages, pour
envoyer sans quitter avant de passer sur lautre Mac.
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
