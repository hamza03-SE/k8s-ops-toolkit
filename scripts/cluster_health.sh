#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

CONTEXT=""
NAMESPACE=""

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Vérifie la santé d'un cluster Kubernetes : état des nodes et pods en erreur.

OPTIONS:
    -c, --context CONTEXT     Contexte kubectl à utiliser (défaut: contexte courant)
    -n, --namespace NS        Limiter la vérification à un namespace (défaut: tous)
    -h, --help                Affiche cette aide
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--context)
            CONTEXT="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Option inconnue: $1"
            usage
            exit 1
            ;;
    esac
done

check_dependency kubectl
check_dependency jq

KUBECTL_ARGS=()
[[ -n "$CONTEXT" ]] && KUBECTL_ARGS+=(--context "$CONTEXT")

EXIT_CODE=0

# ---- V1 : vérification des nodes ----
log_info "Verification des nodes ..."

NODES_JSON=$(kubectl "${KUBECTL_ARGS[@]}" get nodes -o json)

NOT_READY_NODES=$(echo "$NODES_JSON" | jq -r '
    .items[] |
    select(.status.conditions[] | select(.type=="Ready" and .status!="True")) |
    .metadata.name
')

if [[ -n "$NOT_READY_NODES" ]]; then
    log_error "Nodes NotReady détectés :"
    echo "$NOT_READY_NODES" | while read -r node; do
        echo "  - $node"
    done
    EXIT_CODE=1
else
    log_info "Tous les nodes sont Ready."
fi

# ---- V2 : détection complète des pods en erreur ----
log_info "Vérification des pods..."

NS_FLAG="--all-namespaces"
[[ -n "$NAMESPACE" ]] && NS_FLAG="--namespace=$NAMESPACE"

PODS_JSON=$(kubectl "${KUBECTL_ARGS[@]}" get pods $NS_FLAG -o json)

# 1. Container waiting (image/config/crash)
WAITING_PODS=$(echo "$PODS_JSON" | jq -r '
    .items[] as $pod |
    ($pod.status.containerStatuses // [])[] |
    select((.state.waiting.reason // "") | test(
        "CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|CreateContainerError|InvalidImageName"
    )) |
    "\($pod.metadata.namespace)/\($pod.metadata.name): \(.state.waiting.reason)"
')

# 2. Container terminated (erreur, OOM, statut inconnu, deadline)
TERMINATED_PODS=$(echo "$PODS_JSON" | jq -r '
    .items[] as $pod |
    ($pod.status.containerStatuses // [])[] |
    select((.state.terminated.reason // "") | test(
        "Error|OOMKilled|ContainerStatusUnknown|DeadlineExceeded"
    )) |
    "\($pod.metadata.namespace)/\($pod.metadata.name): \(.state.terminated.reason)"
')

# 3. Phase globale problématique du pod
PHASE_ISSUES=$(echo "$PODS_JSON" | jq -r '
    .items[] |
    select(.status.phase == "Pending" or .status.phase == "Failed" or .status.phase == "Unknown") |
    "\(.metadata.namespace)/\(.metadata.name): Phase=\(.status.phase)"
')

# 4. Terminating bloqué depuis plus de 10 minutes
STUCK_TERMINATING=$(echo "$PODS_JSON" | jq -r --argjson threshold 600 '
    now as $now |
    .items[] |
    select(.metadata.deletionTimestamp != null) |
    select(($now - (.metadata.deletionTimestamp | fromdateiso8601)) > $threshold) |
    "\(.metadata.namespace)/\(.metadata.name): Terminating bloqué depuis plus de 10min"
')

# 5. Redémarrages excessifs (crash loop "caché" même si Running)
HIGH_RESTART_PODS=$(echo "$PODS_JSON" | jq -r --argjson threshold 5 '
    .items[] as $pod |
    ($pod.status.containerStatuses // [])[] |
    select(.restartCount > $threshold) |
    "\($pod.metadata.namespace)/\($pod.metadata.name): \(.restartCount) redémarrages"
')

# 6. Pods évincés
EVICTED_PODS=$(echo "$PODS_JSON" | jq -r '
    .items[] |
    select(.status.reason == "Evicted") |
    "\(.metadata.namespace)/\(.metadata.name): Evicted"
')

ALL_ERRORS_RAW=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$WAITING_PODS" "$TERMINATED_PODS" "$PHASE_ISSUES" \
    "$STUCK_TERMINATING" "$HIGH_RESTART_PODS" "$EVICTED_PODS" \
    | grep -v '^$' || true)

# Regroupe toutes les raisons d'un même pod sur une seule ligne
ALL_ERRORS=$(echo "$ALL_ERRORS_RAW" | awk -F': ' '
    { reasons[$1] = reasons[$1] ? reasons[$1] ", " $2 : $2 }
    END { for (pod in reasons) print pod ": " reasons[pod] }
' | sort)

if [[ -n "$ALL_ERRORS" ]]; then
    log_error "Pods en erreur détectés :"
    echo "$ALL_ERRORS" | column -t -s ':'
    EXIT_CODE=1
else
    log_info "Aucun pod en erreur."
fi

exit "$EXIT_CODE"
