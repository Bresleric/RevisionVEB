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

Destination par défaut : `~/Documents/Paie Arhia/<dossier>/<AAAA-MM>/<type>/`,
avec un `index.csv` récapitulatif à la racine.

Prérequis : Node.js (LTS) et Google Chrome. Sans Chrome, lancer une fois
`npx playwright install chromium` dans `scripts/arhia`.

Les libellés de type (« Bulletins », « Etats de paie », « Attestations
fiscales »…) viennent des constantes de l'application Arhia ; un type inconnu
est rangé dans `type-N` et pourra être renommé une fois identifié.
