#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

CONTEXT=""
NAMESPACE="default"
RESOURCE_TYPE="deployment"
RESOURCE_NAME=""
TIMEOUT="300"

usage() {
     cat << EOF
Usage: $(basename "$0") --name NOM [OPTIONS]

Attend qu'un deploiement Kubernetes (ou daemonset/statefulset) soit pret.

OPTIONS:
    --name NAME                  Nom de la ressource a surveiller (obligatoire)
    -t, --type TYPE              Type de ressource: deployment|daemonset|statefulset (defaut: deployment)
    -c, --context CONTEXT        Contexte kubectl a utiliser (defaut: contexte courant)
    -n, --namespace NS           Namespace de la ressource (defaut: default)
    --timeout SECONDS            Timeout en secondes (defaut: 300)
    -h, --help                   Affiche cette aide
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            RESOURCE_NAME="$2"
            shift 2
            ;;
        -t|--type)
            RESOURCE_TYPE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
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

if [[ -z "$RESOURCE_NAME" ]]; then
    log_error "L'option --name est obligatoire."
    usage
    exit 1
fi

case "$RESOURCE_TYPE" in
    deployment|daemonset|statefulset)
        ;;
    *)
       log_error "Type de ressource invalide: $RESOURCE_TYPE (attendu: deployment|daemonset|statefulset)"
       exit 1
       ;;
esac

KUBECTL_ARGS=()
[[ -n "$CONTEXT"  ]] && KUBECTL_ARGS+=(--context "$CONTEXT")

log_info "Verification de l'existance de ${RESOURCE_TYPE}/${RESOURCE_NAME} dans le namespace ${NAMESPACE}..."

if ! kubectl "${KUBECTL_ARGS[@]}" get "$RESOURCE_TYPE" "$RESOURCE_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_error "${RESOURCE_TYPE}/${RESOURCE_NAME} introuvable "
    exit 1
fi

log_info "Attendre rollout de ${RESOURCE_TYPE}/${RESOURCE_NAME} (timeout: ${TIMEOUT}s)..."

if kubectl "${KUBECTL_ARGS[@]}" rollout status "${RESOURCE_TYPE}/${RESOURCE_NAME}" -n "${NAMESPACE}" --timeout="${TIMEOUT}s"; then
    log_info "Rollout de ${RESOURCE_TYPE}/${RESOURCE_NAME} termine avec succes."
    exit 0
else
    log_error "Rollout de ${RESOURCE_TYPE}/${RESOURCE_NAME} echoue ou timeout  depasse"
    log_warn "Derniers evenements lies a cette ressource :"

EVENTS=$(kubectl "${KUBECTL_ARGS[@]}" get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | grep "${RESOURCE_NAME}" || true)
if [[ -n "$EVENTS" ]]; then
    echo "$EVENTS" | tail -5
else
    log_warn "Aucun evenement recent trouve."
fi
    exit 1
fi

