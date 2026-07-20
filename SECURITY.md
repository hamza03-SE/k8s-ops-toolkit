# Politique de sécurité

## Signaler une vulnérabilité

Merci de ne PAS ouvrir une issue publique pour signaler une faille de sécurité.
Contactez directement le mainteneur du projet.

## Permissions requises

`cluster-health.sh` et `wait-for-rollout.sh` nécessitent uniquement un accès
en lecture (get/list) sur les ressources `nodes`, `pods`, `events`, et les
ressources `apps` (deployments/daemonsets/statefulsets).

`log-cleaner.sh` peut supprimer des données (journald, Elasticsearch, Loki),
mais uniquement avec le flag explicite `--apply`. Le mode par défaut est un
dry-run qui n'exécute aucune action destructive.

`deploy-notify.sh` nécessite des identifiants SMTP, à fournir exclusivement
via variables d'environnement, jamais en argument de ligne de commande.

## Bonnes pratiques

- Ne jamais commiter de kubeconfig, token, ou mot de passe dans ce repo
- Toujours tester `log-cleaner.sh` en dry-run avant tout `--apply`
- Utiliser un ServiceAccount dédié avec permissions minimales en CI/CD
- Ce repo est scanné automatiquement (ShellCheck + Gitleaks) à chaque push
