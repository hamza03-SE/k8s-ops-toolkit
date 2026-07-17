# K8s-Ops-Toolkit

Suite d'outils CLI en Bash pour l'automatisation de la supervision et de l'administration Kubernetes multi-cluster.

![Bash](https://img.shields.io/badge/Bash-4%2B-4EAA25?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Status](https://img.shields.io/badge/status-en%20développement-yellow)

> 🚧 Projet en cours de développement actif. `cluster-health.sh` est fonctionnel et validé sur des clusters réels (K3s et kubeadm). Les autres outils sont en cours d'écriture — voir [Roadmap](#roadmap--état-davancement).

---

## Sommaire

- [Le problème résolu](#le-problème-résolu)
- [Les outils du toolkit](#les-outils-du-toolkit)
- [Installation](#installation)
- [Utilisation rapide](#utilisation-rapide)
- [Options disponibles](#options-disponibles)
- [Exemples concrets](#exemples-concrets)
- [Architecture du repo](#architecture-du-repo)
- [Sécurité](#sécurité)
- [Qualité et tests](#qualité-et-tests)
- [Roadmap / état d'avancement](#roadmap--état-davancement)
- [Licence](#licence)

---

## Le problème résolu

Dans un environnement Kubernetes multi-cluster (DEV / TEST / PROD, ou plusieurs clusters distincts), l'administration quotidienne repose souvent sur des commandes `kubectl` lancées manuellement, une par une, cluster par cluster :

- Vérifier si les nodes sont en bonne santé
- Chercher les pods en erreur (CrashLoopBackOff, Pending, OOMKilled, Evicted...)
- Attendre qu'un déploiement soit prêt après un push CI/CD
- Nettoyer des logs qui s'accumulent
- Vérifier manuellement si un déploiement a réussi

C'est répétitif, source d'erreur humaine, et ne produit pas de sortie exploitable automatiquement dans une pipeline. **K8s-Ops-Toolkit** automatise ces tâches avec des scripts génériques, testés, et intégrables en CI/CD.

---

## Les outils du toolkit

| Script | Rôle | Statut |
|---|---|---|
| `cluster-health.sh` | Diagnostic de santé : état des nodes + détection multi-critères des pods en erreur | ✅ Fonctionnel |
| `wait-for-rollout.sh` | Attend qu'un déploiement soit prêt, avec timeout configurable | 🔲 À venir |
| `log-cleaner.sh` | Nettoyage standardisé des logs (journald, Elasticsearch), avec `--dry-run` | 🔲 À venir |
| `deploy-notify.sh` | Notification Slack/Discord de succès/échec de déploiement | 🔲 À venir |

### `cluster-health.sh` en détail

Vérifie l'état des nodes (`Ready` / `NotReady`) et détecte les pods en erreur selon **7 catégories** de statuts réels renvoyés par l'API Kubernetes :

- Container en attente : `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull`, `CreateContainerConfigError`, `CreateContainerError`, `InvalidImageName`
- Container terminé en erreur : `Error`, `OOMKilled`, `ContainerStatusUnknown`, `DeadlineExceeded`
- Phase globale problématique : `Pending`, `Failed`, `Unknown`
- Pods bloqués en `Terminating` depuis plus de 10 minutes
- Redémarrages excessifs (crash loop "caché", même si le pod affiche `Running`)
- Pods évincés (`Evicted`)

Les résultats sont consolidés **une ligne par pod**, avec toutes ses causes regroupées, pour une lecture rapide même sur un cluster avec de nombreux problèmes simultanés.

Exécute uniquement des opérations en **lecture seule** (`get`, `list`) — aucun risque de modification ou de suppression sur le cluster.

---

## Installation

### Prérequis

| Outil | Rôle | Installation |
|---|---|---|
| `kubectl` | Interagir avec l'API Kubernetes | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| `jq` | Parser le JSON retourné par `kubectl -o json` | `sudo apt install jq` / `brew install jq` |
| `git` | Récupérer le projet | `sudo apt install git` / `brew install git` |
| Un accès kubeconfig valide | Se connecter à un cluster | Fourni par l'admin du cluster, ou récupéré soi-même (voir plus bas) |

### Utilisateurs Windows

Les scripts sont écrits en Bash et ne peuvent pas s'exécuter nativement sur Windows. Utilisez **WSL** (Windows Subsystem for Linux), officiel et gratuit :

```powershell
# Dans PowerShell, en administrateur
wsl --install
```

Redémarrez, puis ouvrez le terminal **Ubuntu** installé automatiquement — toutes les commandes ci-dessous s'exécutent dans ce terminal.

### Installer les prérequis (Debian/Ubuntu, y compris via WSL)

```bash
sudo apt update
sudo apt install -y git jq curl openssh-client

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Vérifier :
```bash
kubectl version --client
```

### Récupérer le toolkit

```bash
git clone https://github.com/TON_USERNAME/k8s-ops-toolkit.git
cd k8s-ops-toolkit
```

**⚠️ Bonne pratique de sécurité** : évitez toute méthode d'installation type `curl ... | bash`. Clonez le repo et lisez le code avant de l'exécuter — c'est justement l'intérêt d'un outil open source.

---

## Utilisation rapide

### Cas le plus courant : vous avez déjà un accès `kubectl` fonctionnel

Si vous travaillez déjà dans un environnement Kubernetes (accès déjà configuré), **aucune configuration supplémentaire n'est nécessaire** :

```bash
scripts/cluster-health.sh
```

Le script utilise automatiquement :
- le contexte actif par défaut de votre kubeconfig
- tous les namespaces du cluster

### Vous n'avez pas encore d'accès configuré à votre cluster

Si vous devez récupérer l'accès à un cluster distant (ex: cluster kubeadm sur une VM via SSH) :

```bash
# Récupérer le kubeconfig depuis le control-plane (kubeadm)
ssh -p PORT user@IP_DU_CLUSTER "sudo cat /etc/kubernetes/admin.conf" > ~/mon-cluster.yaml

# L'utiliser
export KUBECONFIG=~/mon-cluster.yaml
kubectl get nodes   # vérifie que la connexion fonctionne

# Utiliser le toolkit
scripts/cluster-health.sh
```

Pour un cluster K3s, le fichier équivalent se trouve à `/etc/rancher/k3s/k3s.yaml` (attention : remplacer `127.0.0.1` par l'IP réelle du control-plane dans le fichier récupéré).

---

## Options disponibles

```
Usage: cluster-health.sh [OPTIONS]

OPTIONS:
    -c, --context CONTEXT     Contexte kubectl à utiliser (défaut: contexte courant)
    -n, --namespace NS        Limiter la vérification à un namespace (défaut: tous)
    -h, --help                Affiche cette aide
```

Toutes les options sont **optionnelles** — le script fonctionne avec des valeurs par défaut sensées, sans rien exiger de l'utilisateur.

---

## Exemples concrets

```bash
# Vue globale du cluster actif (tous namespaces)
scripts/cluster-health.sh

# Un seul namespace
scripts/cluster-health.sh --namespace production

# Cibler un cluster précis parmi plusieurs dans son kubeconfig
scripts/cluster-health.sh --context nom-du-contexte

# Combiner les deux
scripts/cluster-health.sh --context prod-cluster --namespace ticketing
```

### Exemple de sortie

```
[INFO] Verification des nodes ...
[ERROR] Nodes NotReady détectés :
  - worker1
  - worker2
[INFO] Vérification des pods...
[ERROR] Pods en erreur détectés :
ticketing/auth-deployment-74958c5556-x54hw   ContainerStatusUnknown, Phase=Failed, 146 redémarrages, Evicted
ticketing/redis-0                            Terminating bloqué depuis plus de 10min
```

Code de sortie `0` si tout va bien, `1` si un problème est détecté — directement exploitable dans une pipeline CI/CD :
```bash
scripts/cluster-health.sh || echo "Cluster en mauvaise santé, alerte à envoyer"
```

---

## Architecture du repo

```
k8s-ops-toolkit/
├── README.md                    # Ce fichier
├── LICENSE                      # MIT
├── scripts/
│   ├── cluster-health.sh        # ✅ Fonctionnel
│   ├── wait-for-rollout.sh      # 🔲 À venir
│   ├── log-cleaner.sh           # 🔲 À venir
│   └── deploy-notify.sh         # 🔲 À venir
├── lib/
│   └── common.sh                # Fonctions partagées (logging, vérification de dépendances)
├── tests/
│   └── cluster_health.bats      # Tests automatisés (bats-core)
├── .github/
│   └── workflows/               # 🔲 CI (lint + tests) à venir
└── .shellcheckrc                # Règles de lint Bash
```

`lib/common.sh` centralise les fonctions réutilisées par tous les scripts (`log_info`, `log_error`, `log_warn`, `check_dependency`) pour éviter la duplication de code entre chaque outil.

---

## Sécurité

Ce toolkit est conçu pour être utilisé en confiance dans des environnements réels, y compris en production. Points clés :

- **Lecture seule** : `cluster-health.sh` n'exécute que des opérations `get`/`list`, jamais de `delete`, `patch` ou `apply`. Aucun risque de modification du cluster.
- **Zéro secret en dur** : aucune valeur sensible n'est codée dans le script. Les futurs outils (`deploy-notify.sh`) liront les webhooks depuis des variables d'environnement exclusivement.
- **Quoting strict des variables** : toutes les entrées utilisateur (`--context`, `--namespace`) sont correctement quotées dans les appels `kubectl`, empêchant l'injection de commande.
- **Permissions minimales requises** : le script n'a besoin que d'un accès `get`/`list` sur les ressources `nodes` et `pods`. Exemple de `ClusterRole` minimal :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-ops-toolkit-readonly
rules:
- apiGroups: [""]
  resources: ["nodes", "pods"]
  verbs: ["get", "list"]
```

- **Pas d'installation en `curl | bash`** : le code doit toujours être cloné et lisible avant exécution.
- **Signaler une vulnérabilité** : merci de ne pas ouvrir d'issue publique. Contactez directement le mainteneur (coordonnées à ajouter).

---

## Qualité et tests

- **Lint** : le code est prévu pour être vérifié avec [ShellCheck](https://www.shellcheck.net/) à chaque push (`.shellcheckrc` déjà en place, workflow CI à venir en Phase 7)
- **Tests automatisés** : suite de tests [bats-core](https://github.com/bats-core/bats-core) couvrant le parsing des arguments (`--help`, options invalides)

Lancer les tests localement :
```bash
sudo apt install -y bats
bats tests/cluster_health.bats
```

Vérifier la syntaxe d'un script avant de le committer :
```bash
bash -n scripts/cluster-health.sh
```

---

## Roadmap / état d'avancement

| Phase | Contenu | Statut |
|---|---|---|
| 0 | Structure du repo, licence, `common.sh` | ✅ Fait |
| 1 | `cluster-health.sh` V1 — check des nodes | ✅ Fait |
| 2 | `cluster-health.sh` V2 — détection complète des pods en erreur | ✅ Fait, validé sur clusters réels (K3s + kubeadm) |
| 3 | `cluster-health.sh` V3 — `--all-contexts` (multi-cluster) + sortie `--json` | 🔲 En cours |
| 4 | `wait-for-rollout.sh` | 🔲 À venir |
| 5 | `log-cleaner.sh` (avec `--dry-run`) | 🔲 À venir |
| 6 | `deploy-notify.sh` | 🔲 À venir |
| 7 | CI/CD complet (shellcheck, bats, scan de sécurité Trivy/Gitleaks, branch protection) | 🔲 À venir |
| 8 | Documentation finale et présentation portfolio | 🔲 À venir |

Évolutions futures envisagées : mode `--watch` (monitoring continu), export de métriques Prometheus, configuration via fichier YAML, packaging binaire.

---

## Licence

Ce projet est sous licence [MIT](LICENSE) — libre de réutilisation, modification et distribution.

## Contribuer

Les contributions passent par le mécanisme standard **Fork + Pull Request** de GitHub. Les push directs sur `main` sont réservés au mainteneur du projet.
