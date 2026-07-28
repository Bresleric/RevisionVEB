# RevisionVEB

Application macOS de révision comptable pour les restaurants PlanB.

- **Développement** sur le Mac mini, avec Xcode.
- **Déploiement** automatique vers le MacBook Air, via GitHub.
- **Données** dans Supabase, accessibles depuis les deux machines.
  SwiftData ne sert que de cache local.

---

## Aide-mémoire

Toutes les commandes se lancent depuis la racine du projet.
Chaque script répond à `--help`.

### L'application du Dock

```bash
./install-app.sh
```

Compile en Release et installe dans `/Applications`. C'est cette copie que
pointe l'icône du Dock — pas celle d'Xcode, dont le chemin change et qu'un
*Clean* efface.

| Besoin | Commande |
|---|---|
| Mettre à jour l'app du Dock | `./install-app.sh` |
| Proposer la mise à jour après chaque commit | `./install-app.sh --install-hook` |
| **Ne plus proposer la mise à jour** | `./install-app.sh --uninstall-hook` |

Le hook n'agit que sur les commits touchant `RevisionVEB/`, ne lance jamais deux
compilations à la fois, et ne demande confirmation que si l'application est
ouverte. Sinon il installe en silence.

### Le déploiement vers le MacBook Air

```bash
./deploy-watch.sh --install
```

Installe un agent qui surveille GitHub et réinstalle l'app à chaque évolution
poussée depuis le Mac mini. Démarre tout seul à l'ouverture de session.

| Besoin | Commande |
|---|---|
| Voir ce que fait l'agent | `tail -f ~/Library/Logs/revisionveb-deploy.log` |
| Forcer une vérification | `./deploy-watch.sh --once` |
| **Désactiver l'agent** | `./deploy-watch.sh --uninstall` |

À n'installer que sur le MacBook Air. Sur le Mac mini il tournerait en boucle :
c'est la machine qui pousse, son `HEAD` est en avance sur GitHub entre le commit
et le push.

### Supabase

Deux scripts SQL, à coller dans **Supabase Studio → SQL Editor**. Ils sont
idempotents : les rejouer ne casse rien.

| Fichier | Rôle |
|---|---|
| `supabase_schema.sql` | Tables du travail d'audit et points en suspens |
| `supabase_storage.sql` | Dépôt des pièces justificatives (bucket privé) |

Ces scripts ne peuvent pas être exécutés depuis l'application : la clé
publishable n'a pas les droits nécessaires.

---

## Fonctionnement de la synchronisation

Au lancement, l'application envoie d'abord ses données locales vers Supabase,
puis recharge l'ensemble. Les données importées (dossiers, exercices, balance)
sont remplacées ; le travail d'audit est fusionné par identifiant, jamais vidé.
Quand les deux côtés portent une date de modification, le plus récent gagne.

Les pièces justificatives transitent par Supabase Storage. Cliquer sur une
référence absente de la machine la récupère avant de l'ouvrir.

### Limites connues

- **Les suppressions ne se propagent pas**, sauf pour les points en suspens.
  Supprimer un contrôle sur un Mac ne l'efface pas sur l'autre.
- **Le bilan de synchronisation** s'affiche en fin de lancement dans la console
  Xcode. Il nomme la table, le code PostgreSQL et la cause de chaque échec.
