# K8s-Ops-Toolkit — Documentation complète

![CI](https://github.com/hamza03-SE/k8s-ops-toolkit/actions/workflows/ci.yml/badge.svg)

Suite d'outils CLI en Bash pour l'automatisation de la supervision et de l'administration Kubernetes multi-cluster.

**Version documentée** : projet terminé — 9 phases sur 9 complétées.

> 💡 **Astuce** : chaque script du toolkit est auto-documenté. Ajoute `--help` à n'importe quelle commande pour voir toutes les options disponibles :
> ```bash
> scripts/cluster-health.sh --help
> scripts/wait-for-rollout.sh --help
> scripts/log-cleaner.sh --help
> scripts/deploy-notify.sh --help
> ```

---

## Sommaire

1. [Présentation du projet](#1-présentation-du-projet)
2. [Le problème résolu](#2-le-problème-résolu)
3. [Les outils disponibles](#3-les-outils-disponibles)
4. [Installation](#4-installation)
5. [Configuration de l'accès à un cluster](#5-configuration-de-laccès-à-un-cluster)
6. [`cluster-health.sh` — Documentation complète](#6-cluster-healthsh--documentation-complète)
7. [`wait-for-rollout.sh` — Documentation complète](#7-wait-for-rolloutsh--documentation-complète)
8. [`log-cleaner.sh` — Documentation complète](#8-log-cleanersh--documentation-complète)
9. [`deploy-notify.sh` — Documentation complète](#9-deploy-notifysh--documentation-complète)
10. [Utiliser le toolkit dans un projet réel](#10-utiliser-le-toolkit-dans-un-projet-réel)
11. [Intégration CI/CD](#11-intégration-cicd)
12. [Sécurité](#12-sécurité)
13. [Architecture technique](#13-architecture-technique)
14. [Qualité et tests](#14-qualité-et-tests)
15. [Dépannage (erreurs fréquentes)](#15-dépannage-erreurs-fréquentes)
16. [État d'avancement et bilan du projet](#16-état-davancement-et-bilan-du-projet)

---

## 1. Présentation du projet

K8s-Ops-Toolkit est une collection de scripts Bash professionnels, conçus pour automatiser les tâches répétitives de supervision et d'administration d'un environnement Kubernetes multi-cluster : santé des nodes et pods, attente de déploiement, nettoyage de logs, notifications de déploiement par email — avec une intégration CI/CD native (codes de sortie standardisés, sortie JSON).

Le projet est **open source**, sous licence **MIT**, pensé dès le départ pour être **générique** : aucune valeur codée en dur, fonctionne sur n'importe quel cluster (K3s, kubeadm, EKS, GKE, minikube) tant qu'un accès `kubectl` valide existe.

Le projet est aujourd'hui **complet** : les 4 outils sont fonctionnels et validés, la CI/CD (lint, tests, scan de sécurité) est en place et verte, et la documentation est à jour.

---

## 2. Le problème résolu

Dans un environnement Kubernetes multi-cluster, l'administration quotidienne repose souvent sur des commandes `kubectl` lancées manuellement, une par une, cluster par cluster :

- Vérifier si les nodes sont en bonne santé
- Chercher les pods en erreur
- Attendre qu'un déploiement soit prêt après un push CI/CD
- Nettoyer des logs qui s'accumulent
- Vérifier manuellement si un déploiement a réussi

C'est répétitif, source d'erreur humaine, et ne produit pas de sortie exploitable automatiquement dans une pipeline. Chaque outil du toolkit répond à une étape précise de ce cycle.

---

## 3. Les outils disponibles

| Script | Rôle | Statut |
|---|---|---|
| `cluster-health.sh` | Diagnostic de santé : nodes + détection multi-critères des pods en erreur, mono ou multi-cluster, sortie texte ou JSON | ✅ Fonctionnel, validé sur clusters réels |
| `wait-for-rollout.sh` | Attend qu'un déploiement/daemonset/statefulset soit prêt, avec timeout et affichage des événements en cas d'échec | ✅ Fonctionnel, validé sur clusters réels |
| `log-cleaner.sh` | Nettoyage standardisé des logs (journald, Elasticsearch, Loki), avec `--dry-run` par défaut | ✅ Fonctionnel — journald, Elasticsearch et Loki tous validés |
| `deploy-notify.sh` | Notification **par email (SMTP)** de succès/échec de déploiement | ✅ Fonctionnel, validé (envoi réel testé via Gmail SMTP) |

Chaque script est **autonome** — tu peux utiliser un seul outil du toolkit sans avoir besoin des autres, seul `lib/common.sh` est une dépendance partagée.

---

## 4. Installation

### 4.1 Prérequis

| Outil | Rôle | Installation |
|---|---|---|
| `kubectl` | Interagir avec l'API Kubernetes | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| `jq` | Parser le JSON retourné par `kubectl -o json` | `sudo apt install jq` / `brew install jq` |
| `curl` | Envoyer les emails via SMTP (`deploy-notify.sh`), requêtes Elasticsearch/Loki | Préinstallé sur la plupart des systèmes |
| `git` | Récupérer le projet | `sudo apt install git` / `brew install git` |
| Bash 4+ | Exécuter les scripts | Préinstallé sur la plupart des systèmes Linux/macOS |

### 4.2 Utilisateurs Windows

Les scripts sont écrits en Bash et ne s'exécutent pas nativement sur Windows. Utilise **WSL** (Windows Subsystem for Linux), officiel et gratuit :

```powershell
# Dans PowerShell, en administrateur
wsl --install
```

Redémarre, puis ouvre le terminal **Ubuntu** installé automatiquement. Toutes les commandes de ce document s'exécutent dans ce terminal.

### 4.3 Installer les prérequis (Debian/Ubuntu, y compris via WSL)

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

### 4.4 Récupérer le toolkit

```bash
git clone https://github.com/hamza03-SE/k8s-ops-toolkit.git
cd k8s-ops-toolkit
```

> **Bonne pratique de sécurité** : évite toute méthode d'installation en `curl ... | bash`. Clone le repo et lis le code avant de l'exécuter — c'est l'intérêt même d'un outil open source.

---

## 5. Configuration de l'accès à un cluster

### 5.1 Cas le plus courant : tu as déjà un accès `kubectl` fonctionnel

Si tu travailles déjà dans un environnement Kubernetes, **aucune configuration supplémentaire n'est nécessaire**. Les scripts utilisent automatiquement :
- le contexte actif par défaut de ton kubeconfig
- tous les namespaces (sauf précision contraire)

```bash
scripts/cluster-health.sh
```

### 5.2 Tu dois récupérer l'accès à un cluster distant

**Cluster kubeadm, sur un serveur accessible en SSH :**
```bash
ssh -p PORT_SSH user@IP_DU_SERVEUR "sudo cat /etc/kubernetes/admin.conf" > ~/mon-cluster.yaml
export KUBECONFIG=~/mon-cluster.yaml
kubectl get nodes   # vérifie que la connexion fonctionne
```

**Cluster K3s :**
Le fichier équivalent se trouve à `/etc/rancher/k3s/k3s.yaml`. Attention : il contient généralement `server: https://127.0.0.1:6443` — remplace `127.0.0.1` par l'IP réelle du control-plane :
```bash
sed -i "s/127.0.0.1/IP_REELLE/" ~/mon-cluster.yaml
```

### 5.3 Gérer plusieurs clusters simultanément (fusion de kubeconfig)

```bash
# Renommer le contexte si besoin (évite un conflit de nom)
kubectl --kubeconfig ~/mon-cluster.yaml config rename-context NOM_ACTUEL mon-nouveau-cluster

# Fusionner avec le kubeconfig existant
KUBECONFIG=~/.kube/config:~/mon-cluster.yaml kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config ~/.kube/config.bak
mv ~/.kube/config-merged ~/.kube/config

# Vérifier
kubectl config get-contexts
```

### 5.4 Vérifier la connectivité réseau avant tout test

```bash
curl -k https://IP_DU_CLUSTER:6443/version
```
Si ça timeout, le firewall du serveur bloque probablement le port 6443 — il faudra soit l'ouvrir, soit passer par un tunnel SSH (`ssh -L 6443:localhost:6443 user@serveur`).

---

## 6. `cluster-health.sh` — Documentation complète

### 6.1 Ce qu'il fait

Vérifie l'état des nodes (`Ready` / `NotReady`) et détecte les pods en erreur selon **7 catégories** de statuts réels renvoyés par l'API Kubernetes, consolidées **une ligne par pod** :

| Catégorie | Statuts détectés |
|---|---|
| Container en attente | `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull`, `CreateContainerConfigError`, `CreateContainerError`, `InvalidImageName` |
| Container terminé en erreur | `Error`, `OOMKilled`, `ContainerStatusUnknown`, `DeadlineExceeded` |
| Phase globale problématique | `Pending`, `Failed`, `Unknown` |
| Suppression bloquée | `Terminating` depuis plus de 10 minutes |
| Instabilité cachée | Redémarrages excessifs (> 5), même si le pod affiche `Running` |
| Éviction | `Evicted` |

Exécute uniquement des opérations en **lecture seule** (`get`, `list`) — aucun risque de modification du cluster.

### 6.2 Options

```
Usage: cluster-health.sh [OPTIONS]

OPTIONS:
    -c, --context CONTEXT     Contexte kubectl à utiliser (défaut: contexte courant)
    -n, --namespace NS        Limiter la vérification à un namespace (défaut: tous)
    -a, --all-contexts        Vérifier tous les contextes du kubeconfig
    -j, --json                Sortie au format JSON (pour intégration CI/CD)
    -h, --help                Affiche cette aide
```

Toutes les options sont **optionnelles**. `--context` et `--all-contexts` sont mutuellement exclusifs.

### 6.3 Exemples

```bash
# Vue globale du cluster actif (tous namespaces)
scripts/cluster-health.sh

# Un seul namespace
scripts/cluster-health.sh --namespace production

# Cibler un cluster précis parmi plusieurs
scripts/cluster-health.sh --context nom-du-contexte

# Scanner tous les clusters du kubeconfig
scripts/cluster-health.sh --all-contexts

# Sortie JSON, exploitable par un autre outil
scripts/cluster-health.sh --all-contexts --json | jq .
```

### 6.4 Exemple de sortie texte

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

### 6.5 Exemple de sortie JSON

```json
[
  {
    "context": "default",
    "status": "issues_detected",
    "not_ready_nodes": ["worker1", "worker2"],
    "pod_errors": [
      {
        "pod": "ticketing/auth-deployment-74958c5556-x54hw",
        "reasons": ["ContainerStatusUnknown", "Phase=Failed", "146 redémarrages", "Evicted"]
      }
    ]
  }
]
```

> **Important** : le JSON ne liste **que** les anomalies détectées — les pods sains (`Running`) ne sont jamais inclus. C'est volontaire : le script est un rapport d'exceptions, pas un inventaire complet. Ça rend la sortie directement exploitable pour une alerte automatisée (`length > 0` = problème).

### 6.6 Codes de sortie

| Code | Signification |
|---|---|
| `0` | Tout va bien sur tous les clusters vérifiés |
| `1` | Au moins un problème détecté (node NotReady ou pod en erreur) sur au moins un cluster |

Exploitable directement dans un script ou une pipeline :
```bash
scripts/cluster-health.sh || echo "Cluster en mauvaise santé, alerte à envoyer"
```

---

## 7. `wait-for-rollout.sh` — Documentation complète

### 7.1 Ce qu'il fait

Attend qu'un déploiement Kubernetes (`Deployment`, `DaemonSet` ou `StatefulSet`) soit effectivement prêt, avec un timeout configurable. Utile en fin de pipeline CI/CD, juste après un `kubectl apply`, pour ne pas enchaîner sur les étapes suivantes (tests, notification) tant que le nouveau déploiement n'est pas réellement opérationnel.

En cas d'échec ou de timeout, affiche automatiquement les derniers événements Kubernetes liés à la ressource, pour aider au diagnostic sans commande supplémentaire.

### 7.2 Options

```
Usage: wait-for-rollout.sh --name NOM [OPTIONS]

OPTIONS:
    --name NAME                Nom de la ressource à surveiller (obligatoire)
    -t, --type TYPE            Type de ressource: deployment|daemonset|statefulset (défaut: deployment)
    -c, --context CONTEXT      Contexte kubectl à utiliser (défaut: contexte courant)
    -n, --namespace NS         Namespace de la ressource (défaut: default)
    --timeout SECONDS          Timeout en secondes (défaut: 300)
    -h, --help                 Affiche cette aide
```

`--name` est **obligatoire** — sans lui, le script échoue immédiatement avec un message clair.

### 7.3 Exemples

```bash
# Attendre un déploiement avec les valeurs par défaut (namespace "default", timeout 300s)
scripts/wait-for-rollout.sh --name mon-app

# Préciser namespace et timeout
scripts/wait-for-rollout.sh --name mon-app --namespace production --timeout 120

# Surveiller un StatefulSet plutôt qu'un Deployment
scripts/wait-for-rollout.sh --name ma-base --type statefulset --namespace production
```

### 7.4 Exemple de sortie — succès

```
[INFO] Verification de l'existance de deployment/mon-app dans le namespace production...
[INFO] Attendre rollout de deployment/mon-app (timeout: 120s)...
deployment "mon-app" successfully rolled out
[INFO] Rollout de deployment/mon-app termine avec succes.
```

### 7.5 Exemple de sortie — échec

```
[INFO] Verification de l'existance de deployment/mon-app dans le namespace production...
[INFO] Attendre rollout de deployment/mon-app (timeout: 30s)...
Waiting for deployment "mon-app" rollout to finish: 0 of 2 updated replicas are available...
error: timed out waiting for the condition
[ERROR] Rollout de deployment/mon-app echoue ou timeout depasse
[WARN] Derniers evenements lies a cette ressource :
production   Warning   BackOff   pod/mon-app-abc123   Back-off restarting failed container
```

### 7.6 Comportements de validation

- Si la ressource n'existe pas → échec **immédiat**, sans attendre le timeout
- Si `--type` n'est pas `deployment`, `daemonset` ou `statefulset` → échec immédiat
- Si aucun événement récent n'est trouvé (ils expirent après ~1h dans Kubernetes) → message explicite plutôt qu'une section vide

### 7.7 Codes de sortie

| Code | Signification |
|---|---|
| `0` | Rollout terminé avec succès |
| `1` | Ressource introuvable, type invalide, rollout échoué ou timeout dépassé |

---

## 8. `log-cleaner.sh` — Documentation complète

### 8.1 Ce qu'il fait

Nettoie les logs qui s'accumulent sur trois cibles possibles : **journald** (logs système du node), **Elasticsearch** (indices anciens d'une stack de logging), ou **Loki** (suppression de logs par sélecteur de labels LogQL). Les trois cibles sont validées sur environnement réel.

> **Sécurité par défaut** : le script fonctionne en **dry-run par défaut** — il affiche uniquement ce qui *serait* supprimé, sans jamais rien supprimer réellement. La suppression effective nécessite le flag explicite `--apply`. Aucun chemin du code n'exécute d'action destructive tant que `--apply` n'est pas passé.

### 8.2 Options

```
Usage: log-cleaner.sh [OPTIONS]

MODE PAR DEFAUT : dry-run (previsualisation uniquement, aucune suppression).
Ajouter --apply pour executer la suppression reelle.

OPTIONS:
    --target TARGET            Cible: journald|elasticsearch|loki (defaut: journald)
    --age DAYS                 Age en jours au-dela duquel supprimer (defaut: 30)
    --es-url URL                URL de l'API Elasticsearch (requis si --target elasticsearch)
    --es-index-prefix PREFIX    Prefixe des indices a cibler (requis si --target elasticsearch)
    --es-password PASSWORD      Mot de passe du compte elastic (requis si --target elasticsearch)
    --loki-url URL              URL de l'API Loki (requis si --target loki)
    --loki-label-selector SEL   Selecteur de label LogQL, ex: '{namespace="ticketing"}' (requis si --target loki)
    --apply                     Execute reellement la suppression (defaut: dry-run)
    -h, --help                  Affiche cette aide
```

Lancé sans aucun argument, le script affiche directement l'aide plutôt que d'échouer silencieusement.

### 8.3 Exemples

```bash
# Previsualiser le nettoyage journald (aucune suppression) — cible et mode par defaut
scripts/log-cleaner.sh

# Previsualiser avec un age precis
scripts/log-cleaner.sh --target journald --age 30

# Executer reellement le nettoyage journald
scripts/log-cleaner.sh --target journald --age 30 --apply

# Nettoyage Elasticsearch (previsualisation puis execution)
scripts/log-cleaner.sh --target elasticsearch \
  --es-url https://localhost:9200 --es-index-prefix logs- \
  --es-password "$ES_PASSWORD" --age 60
scripts/log-cleaner.sh --target elasticsearch \
  --es-url https://localhost:9200 --es-index-prefix logs- \
  --es-password "$ES_PASSWORD" --age 60 --apply

# Nettoyage Loki (previsualisation puis execution)
scripts/log-cleaner.sh --target loki \
  --loki-url http://localhost:3100 \
  --loki-label-selector '{namespace="ticketing"}' --age 14
scripts/log-cleaner.sh --target loki \
  --loki-url http://localhost:3100 \
  --loki-label-selector '{namespace="ticketing"}' --age 14 --apply
```

> **Bonne pratique** : ne jamais passer `--es-password` en clair dans un script versionné ou un historique de commandes partagé. Préférer une variable d'environnement (`--es-password "$ES_PASSWORD"`) alimentée depuis un secret manager ou les secrets CI/CD.

### 8.4 Exemple de sortie — dry-run journald

```
[INFO] === MODE DRY-RUN (aucune suppression ne sera effectuee) ===
[INFO] Ajoute --apply pour executer reellement le nettoyage.
[INFO] Cible: journald | Age: 30 jours
[INFO] Taille actuelle des logs journald:
Archived and active journals take up 512.0M in the file system.
[INFO] [DRY-RUN] Commande qui serait executee : journalctl --vacuum-time=30d
[INFO] [DRY-RUN] Cela supprimerait les entrees journald plus vieilles que 30 jours.
```

### 8.5 Exemple de sortie — dry-run Elasticsearch

```
[INFO] === MODE DRY-RUN (aucune suppression ne sera effectuee) ===
[INFO] Cible: Elasticsearch (https://localhost:9200) | Prefixe: logs- | Age: 60 jours
[INFO] Indices concernes :
  - logs-2026.04.01
  - logs-2026.04.02
[INFO] [DRY-RUN] Ces indices seraient supprimes avec --apply. Aucune suppression effectuee.
```

### 8.6 Exemple de sortie — dry-run Loki

```
[INFO] === MODE DRY-RUN (aucune suppression ne sera effectuee) ===
[INFO] Cible: Loki (http://localhost:3100) | Selecteur: {namespace="ticketing"} | Age: 14 jours
[INFO] [DRY-RUN] Requete de suppression qui serait envoyee a l'API Loki (/loki/api/v1/delete)
[INFO] [DRY-RUN] Aucune suppression effectuee.
```

### 8.7 Comportements de validation

- `--target` doit être l'une des 3 valeurs acceptées, sinon échec immédiat
- `--age` doit être un entier positif, sinon échec immédiat (empêche par exemple `--age -5` ou une faute de frappe de passer silencieusement)
- Les options spécifiques à une cible (`--es-url`, `--es-index-prefix`, `--es-password` pour Elasticsearch ; `--loki-url`, `--loki-label-selector` pour Loki) sont vérifiées comme obligatoires uniquement quand cette cible est sélectionnée

### 8.8 Codes de sortie

| Code | Signification |
|---|---|
| `0` | Prévisualisation ou nettoyage terminé sans erreur |
| `1` | Option invalide, cible injoignable, ou paramètre requis manquant |

### 8.9 Recommandations avant d'utiliser `--apply`

1. Toujours relancer la commande en dry-run juste avant d'ajouter `--apply`, pour vérifier une dernière fois ce qui va être touché
2. Pour un premier test réel sur un environnement sensible, utiliser un seuil d'âge volontairement très élevé (ex: `--age 9999`) afin de valider le mécanisme sans rien supprimer d'important
3. Ne jamais tester `--apply` en premier sur un cluster de production sans validation préalable sur un environnement moins critique

---

## 9. `deploy-notify.sh` — Documentation complète

### 9.1 Ce qu'il fait

Envoie une notification **par email, via un serveur SMTP**, pour signaler le résultat d'un déploiement (succès ou échec), afin d'éviter la vérification manuelle post-déploiement. Conçu pour être appelé en toute fin de pipeline CI/CD, après `wait-for-rollout.sh` et/ou `cluster-health.sh`.

N'exécute aucune opération sur le cluster — uniquement un envoi SMTP via `curl` vers le serveur mail fourni.

### 9.2 Options

```
Usage: deploy-notify.sh --status success|failure --app NOM [OPTIONS]

Envoie une notification de deploiement par email (via SMTP).

Variables d'environnement requises (jamais en argument) :
    SMTP_SERVER       Ex: smtp.gmail.com
    SMTP_PORT         Ex: 587
    SMTP_USER         Adresse d'envoi (ex: alertes@example.com)
    SMTP_PASSWORD     Mot de passe ou mot de passe d'application
    EMAIL_TO          Destinataire(s), separes par des virgules

OPTIONS OBLIGATOIRES:
    --status STATUS          Statut du deploiement: success|failure
    --app NAME                Nom de l'application deployee

OPTIONS:
    --env ENVIRONMENT        Environnement concerne (ex: production, staging)
    --message TEXT           Message additionnel (ex: raison d'un echec)
    -h, --help                Affiche cette aide
```

`--status` et `--app` sont **obligatoires**. Les 5 variables SMTP doivent **toutes** être définies dans l'environnement — jamais passées en argument (pour ne jamais les exposer dans l'historique shell ou les logs CI). `--env` et `--message` sont optionnels.

### 9.3 Exemples

```bash
# Notification de succès
export SMTP_SERVER=smtp.gmail.com
export SMTP_PORT=587
export SMTP_USER=alertes@example.com
export SMTP_PASSWORD='mot-de-passe-application'
export EMAIL_TO=equipe@example.com

scripts/deploy-notify.sh --status success --app mon-app --env production

# Notification d'échec avec message additionnel
scripts/deploy-notify.sh --status failure --app mon-app --env staging \
  --message "Rollout timeout après 180s sur namespace production"
```

> **Mot de passe d'application Gmail** : avec un compte Gmail, `SMTP_PASSWORD` doit être un **mot de passe d'application** dédié (généré depuis les paramètres de sécurité Google), jamais le mot de passe principal du compte. Ce mot de passe doit être traité comme un secret : ne jamais le committer, ne jamais le laisser dans un historique partagé, et le régénérer s'il a pu fuiter (par exemple copié-collé dans un chat, un ticket, ou une capture d'écran).

### 9.4 Utilisation typique en fin de pipeline

```bash
if scripts/wait-for-rollout.sh --name mon-app --namespace prod --timeout 180; then
    scripts/deploy-notify.sh --status success --app mon-app --env production
else
    scripts/deploy-notify.sh --status failure --app mon-app --env production \
        --message "Rollout échoué"
    exit 1
fi
```

### 9.5 Comportements de validation

- `--status` doit être `success` ou `failure`, sinon échec immédiat
- `--app` est obligatoire, sinon échec immédiat
- Si une ou plusieurs variables SMTP (`SMTP_SERVER`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `EMAIL_TO`) sont absentes → échec immédiat, avec la liste précise des variables manquantes
- L'email envoyé varie selon `--status` : objet et emoji distincts pour succès (✅) et échec (❌)
- Un fichier temporaire contenant le corps du message est créé puis supprimé systématiquement (succès comme échec), pour ne jamais laisser de résidu sur le disque

### 9.6 Codes de sortie

| Code | Signification |
|---|---|
| `0` | Email envoyé avec succès |
| `1` | Paramètre invalide/manquant, variable SMTP manquante, ou échec d'envoi de l'email |

---

## 10. Utiliser le toolkit dans un projet réel

### 10.1 En tant qu'utilisateur / administrateur, à la main

```bash
cd k8s-ops-toolkit
scripts/cluster-health.sh --namespace mon-projet
```

### 10.2 Après un déploiement manuel

```bash
kubectl apply -f deployment.yaml
scripts/wait-for-rollout.sh --name mon-app --namespace mon-projet --timeout 180
```

### 10.3 Pipeline de déploiement complète (les 4 outils enchaînés)

```bash
#!/usr/bin/env bash
set -euo pipefail

export SMTP_SERVER=smtp.gmail.com
export SMTP_PORT=587
export SMTP_USER=alertes@example.com
export SMTP_PASSWORD="$SMTP_PASSWORD"   # injecté depuis un secret manager / CI
export EMAIL_TO=equipe@example.com

kubectl apply -f k8s/deployment.yaml

if ./scripts/wait-for-rollout.sh --name mon-app --namespace prod --timeout 180; then
    if ./scripts/cluster-health.sh --namespace prod; then
        ./scripts/deploy-notify.sh --status success --app mon-app --env production
        echo "Déploiement réussi, exécution des tests de fumée..."
        ./smoke-tests.sh
    else
        ./scripts/deploy-notify.sh --status failure --app mon-app --env production \
            --message "Cluster en erreur après déploiement"
        exit 1
    fi
else
    ./scripts/deploy-notify.sh --status failure --app mon-app --env production \
        --message "Rollout échoué ou timeout"
    kubectl rollout undo deployment/mon-app -n prod
    exit 1
fi
```

### 10.4 Surveillance périodique (cron)

```bash
# Vérifie la santé du cluster toutes les 15 minutes
*/15 * * * * /chemin/vers/k8s-ops-toolkit/scripts/cluster-health.sh --all-contexts || echo "Alerte: cluster en erreur" | mail -s "K8s Alert" toi@example.com

# Nettoyage hebdomadaire des logs journald (tous les dimanches a 3h, execution reelle)
0 3 * * 0 /chemin/vers/k8s-ops-toolkit/scripts/log-cleaner.sh --target journald --age 30 --apply
```

---

## 11. Intégration CI/CD

### 11.1 Pipeline CI du projet lui-même

Le repo dispose de sa propre CI (`.github/workflows/ci.yml`), déclenchée à chaque push, avec 3 jobs :

| Job | Rôle |
|---|---|
| `lint` | `shellcheck` sur tous les scripts et `lib/common.sh` |
| `tests` | Exécution de la suite `bats` complète |
| `security-scan` | `Gitleaks` — détection de secrets accidentellement commités |

### 11.2 Exemple GitHub Actions (utilisation du toolkit dans un projet tiers)

```yaml
name: Deploy
on: push

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configurer kubectl
        run: echo "${{ secrets.KUBECONFIG_B64 }}" | base64 -d > ~/.kube/config

      - name: Déployer
        run: kubectl apply -f k8s/

      - name: Attendre le rollout
        run: |
          git clone https://github.com/hamza03-SE/k8s-ops-toolkit.git /tmp/toolkit
          /tmp/toolkit/scripts/wait-for-rollout.sh --name mon-app --namespace prod --timeout 180

      - name: Vérifier la santé du cluster après déploiement
        run: /tmp/toolkit/scripts/cluster-health.sh --namespace prod --json > health-report.json

      - name: Notifier le résultat par email
        if: always()
        env:
          SMTP_SERVER: smtp.gmail.com
          SMTP_PORT: 587
          SMTP_USER: ${{ secrets.SMTP_USER }}
          SMTP_PASSWORD: ${{ secrets.SMTP_PASSWORD }}
          EMAIL_TO: ${{ secrets.EMAIL_TO }}
        run: |
          if [ "${{ job.status }}" = "success" ]; then
            /tmp/toolkit/scripts/deploy-notify.sh --status success --app mon-app --env production
          else
            /tmp/toolkit/scripts/deploy-notify.sh --status failure --app mon-app --env production
          fi

      - name: Publier le rapport
        uses: actions/upload-artifact@v4
        with:
          name: health-report
          path: health-report.json
```

### 11.3 Exemple GitLab CI

```yaml
deploy:
  stage: deploy
  script:
    - kubectl apply -f k8s/
    - git clone https://github.com/hamza03-SE/k8s-ops-toolkit.git /tmp/toolkit
    - /tmp/toolkit/scripts/wait-for-rollout.sh --name mon-app --namespace prod --timeout 180
    - /tmp/toolkit/scripts/cluster-health.sh --namespace prod
  after_script:
    - /tmp/toolkit/scripts/deploy-notify.sh --status "$CI_JOB_STATUS" --app mon-app --env production
  only:
    - main
```

> `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` et `EMAIL_TO` doivent être définis comme variables CI/CD protégées (masquées dans les logs), jamais en clair dans le fichier `.gitlab-ci.yml`.

### 11.4 Exploiter la sortie JSON dans un script d'alerte

```bash
scripts/cluster-health.sh --all-contexts --json > /tmp/health.json

ISSUES=$(jq '[.[] | select(.status == "issues_detected")] | length' /tmp/health.json)

if [[ "$ISSUES" -gt 0 ]]; then
    jq -r '.[] | select(.status == "issues_detected") | .context' /tmp/health.json
    # envoyer une alerte par email ici, via deploy-notify.sh ou un autre mécanisme
fi
```

### 11.5 Nettoyage de logs en fin de pipeline de maintenance

```yaml
cleanup-logs:
  stage: maintenance
  script:
    - scripts/log-cleaner.sh --target elasticsearch --es-url "$ES_URL" --es-index-prefix logs- --es-password "$ES_PASSWORD" --age 60 --apply
  only:
    - schedules
```

> En CI/CD, `--es-password` et `SMTP_PASSWORD` doivent toujours provenir de variables secrètes du pipeline, jamais écrites en clair dans le fichier de configuration.

---

## 12. Sécurité

### 12.1 Principes appliqués

- **Lecture seule pour `cluster-health.sh` et `wait-for-rollout.sh`** : ces deux scripts n'exécutent que des opérations `get`/`list`/`rollout status`, aucun risque de modification du cluster
- **`log-cleaner.sh` supprime réellement des données (journald, Elasticsearch, Loki), mais uniquement avec `--apply` explicite** : le mode par défaut est un dry-run qui n'exécute jamais d'action destructive
- **`deploy-notify.sh` n'a aucun accès au cluster** : simple envoi d'email via SMTP
- **Zéro secret en argument** dans le code — identifiants (`--es-password`, `SMTP_PASSWORD`) passés uniquement en variable d'environnement, jamais codés en dur, et pour `deploy-notify.sh` les identifiants SMTP ne sont **acceptés que via l'environnement**, pas via un flag `--password`, précisément pour éviter qu'ils apparaissent dans l'historique shell (`.bash_history`) ou les logs de process
- **Quoting strict** de toutes les entrées utilisateur (`--context`, `--namespace`, `--name`, `--es-*`, `--loki-*`) dans les appels `kubectl`/`curl`, empêchant l'injection de commande
- **Scan automatique des secrets** (Gitleaks) à chaque push via la CI

### 12.2 Permissions minimales (RBAC)

Le toolkit n'a besoin que d'un accès en lecture pour `cluster-health.sh` et `wait-for-rollout.sh`. Exemple de `ClusterRole` minimal (voir `examples/rbac-readonly.yaml`) :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-ops-toolkit-readonly
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "events"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets"]
  verbs: ["get", "list"]
```

### 12.3 Bonnes pratiques d'installation

- Toujours cloner et lire le code avant exécution — jamais de `curl ... | bash`
- Vérifier la syntaxe avant tout usage en production : `bash -n scripts/nom-du-script.sh`
- Ne jamais committer de kubeconfig, de token, de mot de passe SMTP/Elasticsearch dans le repo
- Ne jamais exporter `SMTP_PASSWORD` en clair dans un terminal partagé ou collé dans un ticket/chat — utiliser un gestionnaire de secrets, et régénérer le mot de passe d'application s'il a pu être exposé
- Pour `log-cleaner.sh`, toujours tester en dry-run avant tout `--apply` (voir [8.9](#89-recommandations-avant-dutiliser---apply))

### 12.4 Protection de la branche `main`

Le repo GitHub applique une règle de protection sur `main` : Pull Request + approbation requises avant fusion, avec bypass réservé aux administrateurs (usage solo). Configuration visible dans **Settings → Branches**.

### 12.5 Signaler une vulnérabilité

Ne pas ouvrir d'issue publique. Contacter directement le mainteneur du projet (voir `SECURITY.md`).

---

## 13. Architecture technique

```
k8s-ops-toolkit/
├── README.md
├── DOCUMENTATION.md
├── SECURITY.md
├── LICENSE                      # MIT
├── scripts/
│   ├── cluster-health.sh        # ✅ Fonctionnel
│   ├── wait-for-rollout.sh      # ✅ Fonctionnel
│   ├── log-cleaner.sh           # ✅ Fonctionnel (journald, ES, Loki)
│   └── deploy-notify.sh         # ✅ Fonctionnel (notification email/SMTP)
├── lib/
│   └── common.sh                # Fonctions partagées
├── examples/
│   └── rbac-readonly.yaml       # RBAC minimal en lecture seule
├── tests/
│   ├── cluster_health.bats
│   ├── wait-for-rollout.bats
│   ├── log-cleaner.bats
│   └── deploy-notify.bats
├── .github/
│   └── workflows/
│       └── ci.yml               # lint + tests + security-scan
└── .shellcheckrc
```

### 13.1 `lib/common.sh` — fonctions partagées

| Fonction | Rôle |
|---|---|
| `log_info` | Affiche un message informatif en vert |
| `log_warn` | Affiche un avertissement en jaune, vers stderr |
| `log_error` | Affiche une erreur en rouge, vers stderr |
| `check_dependency` | Vérifie qu'une commande (`kubectl`, `jq`, `curl`...) est installée, sinon quitte avec un message clair |

Centraliser ces fonctions évite de dupliquer le code de logging dans chaque script du toolkit.

### 13.2 Principes de conception communs à tous les scripts

- `set -euo pipefail` en tête de chaque script (arrêt sur erreur, variable non définie interdite, échec de pipe détecté)
- Toutes les options sont passées via `--flag valeur`, jamais en positionnel
- Toutes les variables utilisateur sont quotées (`"$VAR"`, `"${ARRAY[@]}"`) pour éviter l'injection
- Codes de sortie standardisés : `0` = succès, `1` = problème détecté ou erreur d'usage
- Pour les scripts pouvant supprimer des données (`log-cleaner.sh`), toute action destructive est isolée derrière un flag explicite (`--apply`), jamais exécutée par défaut
- Pour `deploy-notify.sh`, les identifiants sensibles (SMTP) ne sont acceptés **que** via variables d'environnement, jamais via un flag en ligne de commande

---

## 14. Qualité et tests

### 14.1 Lancer les tests

```bash
sudo apt install -y bats
bats tests/cluster_health.bats
bats tests/wait-for-rollout.bats
bats tests/log-cleaner.bats
bats tests/deploy-notify.bats
```

### 14.2 Vérifier la syntaxe d'un script

```bash
bash -n scripts/nom-du-script.sh
```

### 14.3 Lint

```bash
shellcheck scripts/*.sh lib/*.sh
```

Exécuté automatiquement en CI à chaque push.

### 14.4 Couverture des tests

| Script | Tests bats |
|---|---|
| `cluster-health.sh` | Aide, option invalide, incompatibilité `--context`/`--all-contexts`, `--json` sans erreur |
| `wait-for-rollout.sh` | Aide, `--name` obligatoire, type de ressource invalide, option invalide |
| `log-cleaner.sh` | Aide, `--target` invalide, `--age` invalide, options spécifiques manquantes par cible, comportement dry-run par défaut |
| `deploy-notify.sh` | Aide, `--status` invalide, `--app` obligatoire, détection précise de chaque variable SMTP manquante, envoi réussi/échoué (curl stubbé) |

### 14.5 CI/CD du projet

3 jobs exécutés à chaque push sur `.github/workflows/ci.yml` :

| Job | Outil | Statut |
|---|---|---|
| `lint` | shellcheck | ✅ Vert |
| `tests` | bats | ✅ Vert |
| `security-scan` | Gitleaks | ✅ Vert |

---

## 15. Dépannage (erreurs fréquentes)

| Erreur rencontrée | Cause probable | Solution |
|---|---|---|
| `syntax error in conditional expression: unexpected token` | Fins de ligne Windows (CRLF) ou espace manquant avant `]]` | `sed -i 's/\r$//' fichier.sh`, ou vérifier l'espacement autour de `[[ ]]` |
| `Permission denied` à l'exécution | Bit exécutable manquant | `chmod +x scripts/nom-du-script.sh` |
| `unbound variable` sur un tableau | Accolades manquantes : `$VAR[@]` au lieu de `${VAR[@]}` | Toujours utiliser `"${ARRAY[@]}"` pour un tableau |
| `command not found` en lançant le script | Script non trouvé dans le `$PATH` | Utiliser `./nom-du-script.sh` (si dans le dossier) ou `scripts/nom-du-script.sh` (chemin relatif) |
| Push git rejeté (`non-fast-forward`) | Historique local et distant divergents | `git config pull.rebase false && git pull origin main` puis `git push` |
| `SC2086` (shellcheck) sur une variable non quotée | Variable utilisée sans guillemets dans une commande | Toujours quoter : `"$VAR"` au lieu de `$VAR` |
| JSON de `cluster-health.sh` ne montre qu'un seul contexte avec `--all-contexts` | Un seul contexte présent dans le kubeconfig | Normal si un seul cluster est configuré — pas un bug |
| `deploy-notify.sh` échoue avec "Variables d'environnement manquantes" | Une ou plusieurs des 5 variables SMTP ne sont pas exportées | Exporter `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `EMAIL_TO` avant d'appeler le script |
| `deploy-notify.sh` échoue avec "Echec de l'envoi de l'email" | Serveur SMTP injoignable, port bloqué, ou mot de passe d'application invalide/expiré | Vérifier `SMTP_SERVER`/`SMTP_PORT`, régénérer le mot de passe d'application Gmail si besoin |
| "Bypassed rule violations" à chaque push | Comportement normal : admin qui contourne légitimement la branch protection | Rien à corriger — voir section 12.4 |

---

## 16. État d'avancement et bilan du projet

| Phase | Contenu | Statut |
|---|---|---|
| 0 | Structure du repo, licence MIT, `common.sh` | ✅ Fait |
| 1 | `cluster-health.sh` V1 — check des nodes | ✅ Fait |
| 2 | `cluster-health.sh` V2 — détection complète des pods en erreur | ✅ Fait, validé sur clusters réels |
| 3 | `cluster-health.sh` V3 — `--all-contexts` + `--json` | ✅ Fait |
| 4 | `wait-for-rollout.sh` | ✅ Fait, validé sur clusters réels |
| 5 | `log-cleaner.sh` (journald, Elasticsearch, Loki, dry-run par défaut) | ✅ Fait, les 3 cibles validées, tests bats complets |
| 6 | `deploy-notify.sh` (notification par email/SMTP) | ✅ Fait, envoi réel validé via Gmail SMTP |
| 7 | CI/CD complet (shellcheck, bats, Gitleaks, branch protection) | ✅ Fait, 3 jobs verts |
| 8 | Documentation finale et présentation portfolio | ✅ Fait |

**Progression : 9/9 phases terminées. Projet complet.**

### Évolutions futures envisagées (hors périmètre initial)
- Support de canaux additionnels pour `deploy-notify.sh` (Slack/Discord en complément de l'email)
- Mode `--watch` pour un monitoring continu (au lieu d'un snapshot ponctuel)
- Export de métriques vers Prometheus (textfile collector)
- Fichier de configuration YAML pour seuils personnalisés
- Packaging binaire unique (bashly, Homebrew)
- Tests d'intégration sur un second type de cluster (minikube) en plus de kubeadm/K3s

### Pitch pour CV / entretien
> Développement d'une suite d'outils CLI Bash open source (K8s-Ops-Toolkit) automatisant la supervision multi-cluster Kubernetes — santé de cluster, attente de rollout, nettoyage de logs (journald/Elasticsearch/Loki), notifications de déploiement par email (SMTP) — intégrée en CI/CD avec tests automatisés (bats), lint (shellcheck) et scan de sécurité (Gitleaks).

---

*Document généré pour le projet K8s-Ops-Toolkit — reflète l'état final du code, les 9 phases étant terminées.*
