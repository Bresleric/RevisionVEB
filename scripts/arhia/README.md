# Bulletins de paie Combo Pay (Arhia)

Récupère en local tous les bulletins et états de paie publiés sur l'Espace
Employeur Combo Pay (https://combohr.arhia.fr), classés par dossier, mois et
type de document. À relancer chaque mois : les fichiers déjà présents sont
ignorés.

```bash
./scripts/arhia/telecharger-bulletins.sh
```

Une fenêtre de navigateur s'ouvre : connectez-vous vous-même. Le script ne
demande jamais le mot de passe et ne l'enregistre nulle part ; il réutilise
ensuite la session ouverte dans le navigateur pour appeler l'API de
l'application. Le profil du navigateur est conservé dans
`~/Library/Application Support/RevisionVEB/arhia-profile`, ce qui évite en
général de se reconnecter.

| Besoin | Commande |
|---|---|
| Tout depuis janvier 2025 (défaut) | `./scripts/arhia/telecharger-bulletins.sh` |
| Une plage de mois | `… --depuis 202508 --jusqua 202512` |
| Voir la liste sans télécharger | `… --liste` |
| Inclure les versions provisoires | `… --provisoires` |
| Autre dossier de destination | `… --dossier "/Volumes/Archives/Paie"` |
| Garder les réponses brutes de l'API pour analyse | `… --diagnostic` |

Chaque exécution se termine par un récapitulatif du nombre de documents par
mois et par catégorie, ce qui permet de repérer un mois incomplet.

Destination par défaut : `~/Documents/Paie Arhia/<dossier>/<AAAA-MM>/<type>/`,
avec un `index.csv` récapitulatif à la racine.

Prérequis : Node.js (LTS) et Google Chrome. Sans Chrome, lancer une fois
`npx playwright install chromium` dans `scripts/arhia`.

Les catégories de documents reprennent les onglets de la page « États de
paie » de l'application Arhia : `Bulletins` (y compris bulletins d'épargne
salariale), `Syntheses`, `Comptabilite`, `Paiements`, `Cotisations`, `Departs`
(documents de solde de tout compte), `Attestations fiscales` et `Autres
documents`. Un type inconnu est rangé dans `type-N` et pourra être renommé une
fois identifié.

Si rien n'est trouvé ou si l'API renvoie des erreurs, relancer avec
`--diagnostic` : les réponses brutes (sans le jeton de session) sont écrites
dans un fichier temporaire dont le chemin est affiché au démarrage.
