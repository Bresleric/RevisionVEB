#!/bin/bash
# Commit et push : envoi automatique (fermeture, periodique, manuel).
# A lancer sur le Mac Mini :  bash ~/Developer/RevisionVEB/scripts/commit-envoi-automatique.sh

set -e
cd ~/Developer/RevisionVEB

echo "Branche active :"
git branch --show-current
echo ""

git add -A
git status --short
echo ""

git commit -F - <<'MSG'
feat(sync): envoi automatique a la fermeture et toutes les dix minutes

Symptome
- une saisie suivie dun Cmd-Q ne quittait jamais la machine
- lutilisateur croyait legitimement avoir synchronise
- le bouton Quitter lapplication affichait meme Synchronisation avant
  fermeture alors quil ne faisait quun enregistrement local : le message
  mentait sur ce quil faisait

Envoi a la fermeture
- AppDelegate.applicationShouldTerminate retient la fermeture avec
  terminateLater, envoie, puis rend la main
- envoi seul, sans chargement : recuperer les donnees de lautre Mac au
  moment de partir na aucun interet et doublerait lattente
- delai borne a 20 s, au-dela on rend la main. Mieux vaut une fermeture
  qui aboutit quune application qui refuse de se fermer
- le bouton Quitter lapplication se contente desormais denregistrer puis
  de demander la fermeture, le delegue faisant le reste

Envoi periodique
- toutes les dix minutes pendant la session
- couvre ce que la fermeture ne couvre pas : plantage, arret force,
  coupure, ou le gestionnaire de fermeture ne sexecute jamais
- nenvoie que : charger en pleine session ecraserait les saisies en cours
- sans les dedoublonnages, qui suppriment des lignes ici et sur Supabase.
  Justifie au demarrage, ou lon vient de decouvrir letat distant ; pas en
  tache de fond sans que personne ne regarde

Envoi manuel
- Reglages : bouton Synchroniser maintenant, envoi ET chargement, avec
  lheure du dernier envoi
- fullSync accepte force: true pour relancer dans la meme session

Garde commune
- aucun envoi si un rechargement integral est programme, sinon on
  reintroduirait sur Supabase ce quon veut abandonner

Diagnostic
- les identifiants et montants des factures immo reellement transmis sont
  imprimes avant lenvoi. Cest cette mesure, et non les deductions
  successives, qui a permis de localiser le probleme
- verification-donnees-supabase.sql : controle en lecture seule du contenu
  de Supabase apres synchronisation
MSG

git push origin "$(git branch --show-current)"

echo ""
echo "Pousse. Sur le MacBook Air :"
echo "  cd ~/Developer/RevisionVEB && git pull --ff-only"
