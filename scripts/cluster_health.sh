#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

CONTEXT=""
NAMESPACE=""
ALL_CONTEXTS=false
JSON_OUTPUT=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Verifie la sante d'un ou plusieurs clusters Kubernetes : etat des nodes et pods en erreur.

OPTIONS:
    -c, --context CONTEXT     Contexte kubectl a utiliser (defaut: contexte courant)
    -n, --namespace NS        Limiter la verification a un namespace (defaut: tous)
    -a, --all-contexts        Verifier tous les contextes du kubeconfig
    -j, --json                Sortie au format JSON (pour integration CI/CD)
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
        -a|--all-contexts)
            ALL_CONTEXTS=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
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

if [[ "$ALL_CONTEXTS" == true && -n "$CONTEXT" ]]; then
    log_error "Impossible de combiner --context et --all-contexts."
    exit 1
fi

if [[ "$ALL_CONTEXTS" == true ]]; then
    mapfile -t CONTEXTS_TO_CHECK < <(kubectl config get-contexts -o name)
    if [[ ${#CONTEXTS_TO_CHECK[@]} -eq 0 ]]; then
        log_error "Aucun contexte trouve dans le kubeconfig."
        exit 1
    fi
elif [[ -n "$CONTEXT" ]]; then
    CONTEXTS_TO_CHECK=("$CONTEXT")
else
    CURRENT=$(kubectl config current-context 2>/dev/null) || {
        log_error "Aucun contexte courant defini et aucun --context fourni."
        exit 1
    }
    CONTEXTS_TO_CHECK=("$CURRENT")
fi

NS_FLAG="--all-namespaces"
[[ -n "$NAMESPACE" ]] && NS_FLAG="--namespace=$NAMESPACE"

GLOBAL_EXIT_CODE=0
JSON_RESULTS=()

check_cluster() {
    local ctx="$1"
    local ctx_exit_code=0
    local not_ready_nodes=""
    local all_errors=""
    local unreachable=false

    if ! kubectl --context "$ctx" get nodes -o json &>/tmp/cluster_health_probe.json; then
        unreachable=true
        ctx_exit_code=2
    else
        local nodes_json
        nodes_json=$(cat /tmp/cluster_health_probe.json)

        not_ready_nodes=$(echo "$nodes_json" | jq -r '
            .items[] |
            select(.status.conditions[] | select(.type=="Ready" and .status!="True")) |
            .metadata.name
        ')
        [[ -n "$not_ready_nodes" ]] && ctx_exit_code=1

        local pods_json
        pods_json=$(kubectl --context "$ctx" get pods $NS_FLAG -o json)

        local waiting_pods terminated_pods phase_issues stuck_terminating high_restart_pods evicted_pods
        waiting_pods=$(echo "$pods_json" | jq -r '
            .items[] as $pod | ($pod.status.containerStatuses // [])[] |
            select((.state.waiting.reason // "") | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|CreateContainerError|InvalidImageName")) |
            "\($pod.metadata.namespace)/\($pod.metadata.name): \(.state.waiting.reason)"
        ')
        terminated_pods=$(echo "$pods_json" | jq -r '
            .items[] as $pod | ($pod.status.containerStatuses // [])[] |
            select((.state.terminated.reason // "") | test("Error|OOMKilled|ContainerStatusUnknown|DeadlineExceeded")) |
            "\($pod.metadata.namespace)/\($pod.metadata.name): \(.state.terminated.reason)"
        ')
        phase_issues=$(echo "$pods_json" | jq -r '
            .items[] | select(.status.phase == "Pending" or .status.phase == "Failed" or .status.phase == "Unknown") |
            "\(.metadata.namespace)/\(.metadata.name): Phase=\(.status.phase)"
        ')
        stuck_terminating=$(echo "$pods_json" | jq -r --argjson threshold 600 '
            now as $now | .items[] | select(.metadata.deletionTimestamp != null) |
            select(($now - (.metadata.deletionTimestamp | fromdateiso8601)) > $threshold) |
            "\(.metadata.namespace)/\(.metadata.name): Terminating bloque depuis plus de 10min"
        ')
        high_restart_pods=$(echo "$pods_json" | jq -r --argjson threshold 5 '
            .items[] as $pod | ($pod.status.containerStatuses // [])[] |
            select(.restartCount > $threshold) |
            "\($pod.metadata.namespace)/\($pod.metadata.name): \(.restartCount) redemarrages"
        ')
        evicted_pods=$(echo "$pods_json" | jq -r '
            .items[] | select(.status.reason == "Evicted") |
            "\(.metadata.namespace)/\(.metadata.name): Evicted"
        ')

        local raw
        raw=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
            "$waiting_pods" "$terminated_pods" "$phase_issues" \
            "$stuck_terminating" "$high_restart_pods" "$evicted_pods" \
            | grep -v '^$' || true)

        all_errors=$(echo "$raw" | awk -F': ' '
            {
                split(reasons[$1], seen, ", ")
                found = 0
                for (i in seen) if (seen[i] == $2) found = 1
                if (!found) reasons[$1] = reasons[$1] ? reasons[$1] ", " $2 : $2
            }
            END { for (pod in reasons) print pod ": " reasons[pod] }
        ' | sort)

        [[ -n "$all_errors" ]] && ctx_exit_code=1
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        local status_str="ok"
        [[ "$unreachable" == true ]] && status_str="unreachable"
        [[ "$ctx_exit_code" -eq 1 ]] && status_str="issues_detected"

        local not_ready_json="[]"
        [[ -n "$not_ready_nodes" ]] && not_ready_json=$(echo "$not_ready_nodes" | jq -R . | jq -s .)

        local errors_json="[]"
        if [[ -n "$all_errors" ]]; then
            errors_json=$(echo "$all_errors" | jq -R '
                split(": ") | {pod: .[0], reasons: (.[1] | split(", "))}
            ' | jq -s .)
        fi

        JSON_RESULTS+=("$(jq -n \
            --arg context "$ctx" \
            --arg status "$status_str" \
            --argjson not_ready_nodes "$not_ready_json" \
            --argjson pod_errors "$errors_json" \
            '{context: $context, status: $status, not_ready_nodes: $not_ready_nodes, pod_errors: $pod_errors}'
        )")
    else
        log_info "=== Contexte: $ctx ==="
        if [[ "$unreachable" == true ]]; then
            log_error "Cluster injoignable."
        else
            if [[ -n "$not_ready_nodes" ]]; then
                log_error "Nodes NotReady detectes :"
                echo "$not_ready_nodes" | while read -r node; do echo "  - $node"; done
            else
                log_info "Tous les nodes sont Ready."
            fi

            if [[ -n "$all_errors" ]]; then
                log_error "Pods en erreur detectes :"
                echo "$all_errors" | column -t -s ':'
            else
                log_info "Aucun pod en erreur."
            fi
        fi
    fi

    return "$ctx_exit_code"
}

for ctx in "${CONTEXTS_TO_CHECK[@]}"; do
    set +e
    check_cluster "$ctx"
    ctx_result=$?
    set -e
    [[ "$ctx_result" -ne 0 ]] && GLOBAL_EXIT_CODE=1
done

rm -f /tmp/cluster_health_probe.json

if [[ "$JSON_OUTPUT" == true ]]; then
    printf '%s\n' "${JSON_RESULTS[@]}" | jq -s .
fi

exit "$GLOBAL_EXIT_CODE"
