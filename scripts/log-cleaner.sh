#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

TARGET="journald"
AGE_DAYS="30"
ES_URL=""
ES_INDEX_PREFIX=""
ES_PASSWORD=""
LOKI_URL=""
LOKI_LABEL_SELECTOR=""
APPLY=false
REPORT_DIR="${SCRIPT_DIR}/../reports"
REPORT_FILE=""

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Nettoie les logs qui s'accumulent (journald local, Elasticsearch ou Loki).

MODE PAR DEFAUT : dry-run (previsualisation uniquement, aucune suppression).
Ajouter --apply pour executer la suppression reelle.

OPTIONS:
    --target TARGET             Cible: journald|elasticsearch|loki (defaut: journald)
    --age DAYS                  Age en jours au-dela duquel supprimer (defaut: 30)
    --es-url URL                URL de l'API Elasticsearch (requis si --target elasticsearch)
    --es-index-prefix PREFIX    Prefixe des indices a cibler (requis si --target elasticsearch)
    --es-password PASSWORD      Mot de passe du compte elastic (requis si --target elasticsearch)
    --loki-url URL              URL de l'API Loki (requis si --target loki)
    --loki-label-selector SEL   Selecteur de label LogQL (requis si --target loki)
    --apply                     Execute reellement la suppression (defaut: dry-run)
    --report-file PATH          Chemin du rapport JSON (defaut: reports/log-cleaner-TIMESTAMP.json)
    -h, --help                  Affiche cette aide

EXEMPLES:
    $(basename "$0") --target journald --age 30
    $(basename "$0") --target journald --age 30 --apply
    $(basename "$0") --target elasticsearch --es-url https://localhost:9200 --es-index-prefix logs- --es-password 'motdepasse' --age 60
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --age) AGE_DAYS="$2"; shift 2 ;;
        --es-url) ES_URL="$2"; shift 2 ;;
        --es-index-prefix) ES_INDEX_PREFIX="$2"; shift 2 ;;
        --es-password) ES_PASSWORD="$2"; shift 2 ;;
        --loki-url) LOKI_URL="$2"; shift 2 ;;
        --loki-label-selector) LOKI_LABEL_SELECTOR="$2"; shift 2 ;;
        --apply) APPLY=true; shift ;;
        --report-file) REPORT_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            log_error "Option inconnue: $1"
            usage
            exit 1
            ;;
    esac
done

case "$TARGET" in
    journald|elasticsearch|loki) ;;
    *)
        log_error "Cible invalide: $TARGET (attendu: journald|elasticsearch|loki)"
        exit 1
        ;;
esac

if ! [[ "$AGE_DAYS" =~ ^[0-9]+$ ]] || [[ "$AGE_DAYS" -lt 1 ]]; then
    log_error "--age doit etre un nombre entier positif (recu: $AGE_DAYS)"
    exit 1
fi

check_dependency jq

mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TIMESTAMP_FILE=$(date -u +%Y%m%d-%H%M%S)
[[ -z "$REPORT_FILE" ]] && REPORT_FILE="${REPORT_DIR}/log-cleaner-${TIMESTAMP_FILE}.json"
EXECUTED_BY="$(whoami)@$(hostname)"

if [[ "$APPLY" == true ]]; then
    log_warn "=== MODE SUPPRESSION REELLE ACTIVE (--apply) ==="
else
    log_info "=== MODE DRY-RUN (aucune suppression ne sera effectuee) ==="
    log_info "Ajoute --apply pour executer reellement le nettoyage."
fi

write_report() {
    local status="$1"
    local items_json="$2"
    local extra_json="$3"
    [[ -z "$extra_json" ]] && extra_json="{}"

    jq -n \
        --arg timestamp "$TIMESTAMP" \
        --arg executed_by "$EXECUTED_BY" \
        --arg mode "$([[ "$APPLY" == true ]] && echo "apply" || echo "dry-run")" \
        --arg target "$TARGET" \
        --argjson age_days "$AGE_DAYS" \
        --arg status "$status" \
        --argjson items "$items_json" \
        --argjson items_count "$(echo "$items_json" | jq 'length')" \
        --argjson extra "$extra_json" \
        '{
            timestamp: $timestamp,
            executed_by: $executed_by,
            mode: $mode,
            target: $target,
            age_days: $age_days,
            status: $status,
            items_count: $items_count,
            items: $items
        } + $extra' > "$REPORT_FILE"

    log_info "Rapport ecrit : ${REPORT_FILE}"
}

clean_journald() {
    check_dependency journalctl

    log_info "Cible: journald | Age: ${AGE_DAYS} jours"

    local before_usage
    before_usage=$(journalctl --disk-usage 2>&1 | tr -d '\n')
    log_info "Taille actuelle des logs journald: ${before_usage}"

    if [[ "$APPLY" == true ]]; then
        journalctl --vacuum-time="${AGE_DAYS}d"
        local after_usage
        after_usage=$(journalctl --disk-usage 2>&1 | tr -d '\n')
        log_info "Nettoyage termine. ${after_usage}"

        write_report "ok" "[]" \
            "$(jq -n --arg before "$before_usage" --arg after "$after_usage" \
                '{disk_usage_before: $before, disk_usage_after: $after}')"
    else
        log_info "[DRY-RUN] Commande qui serait executee : journalctl --vacuum-time=${AGE_DAYS}d"
        write_report "dry-run" "[]" \
            "$(jq -n --arg before "$before_usage" '{disk_usage_before: $before}')"
    fi
}

clean_elasticsearch() {
    check_dependency curl

    if [[ -z "$ES_URL" || -z "$ES_INDEX_PREFIX" || -z "$ES_PASSWORD" ]]; then
        log_error "--es-url, --es-index-prefix et --es-password sont requis pour --target elasticsearch"
        exit 1
    fi

    log_info "Cible: Elasticsearch (${ES_URL}) | Prefixe: ${ES_INDEX_PREFIX} | Age: ${AGE_DAYS} jours"

    local indices_json
    if ! indices_json=$(curl -sk -u "elastic:${ES_PASSWORD}" "${ES_URL}/_cat/indices/${ES_INDEX_PREFIX}*?format=json" 2>/dev/null); then
        log_error "Impossible de contacter Elasticsearch a ${ES_URL}"
        write_report "failed" "[]" '{"error": "connexion impossible"}'
        exit 1
    fi

    local cutoff_date
    cutoff_date=$(date -d "-${AGE_DAYS} days" +%Y.%m.%d 2>/dev/null || date -v-"${AGE_DAYS}"d +%Y.%m.%d)

    local old_indices_json
    old_indices_json=$(echo "$indices_json" | jq -c --arg prefix "$ES_INDEX_PREFIX" --arg cutoff "$cutoff_date" '
        [.[] | select(.index | startswith($prefix)) |
        select((.index | ltrimstr($prefix)) < $cutoff) |
        {name: .index, size: (."store.size" // "inconnu"), docs: (."docs.count" // "inconnu")}]
    ')

    local count
    count=$(echo "$old_indices_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        log_info "Aucun indice de plus de ${AGE_DAYS} jours trouve."
        write_report "ok" "[]"
        return 0
    fi

    log_info "Indices concernes :"
    echo "$old_indices_json" | jq -r '.[] | "  - \(.name) (\(.size), \(.docs) documents)"'

    if [[ "$APPLY" == true ]]; then
        echo "$old_indices_json" | jq -r '.[].name' | while read -r idx; do
            log_warn "Suppression de l'indice: $idx"
            curl -sk -u "elastic:${ES_PASSWORD}" -X DELETE "${ES_URL}/${idx}" > /dev/null
        done
        log_info "Suppression terminee."
        write_report "ok" "$old_indices_json"
    else
        log_info "[DRY-RUN] Ces indices seraient supprimes avec --apply. Aucune suppression effectuee."
        write_report "dry-run" "$old_indices_json"
    fi
}

clean_loki() {
    check_dependency curl

    if [[ -z "$LOKI_URL" || -z "$LOKI_LABEL_SELECTOR" ]]; then
        log_error "--loki-url et --loki-label-selector sont requis pour --target loki"
        exit 1
    fi

    log_info "Cible: Loki (${LOKI_URL}) | Selecteur: ${LOKI_LABEL_SELECTOR} | Age: ${AGE_DAYS} jours"

    if ! curl -sf "${LOKI_URL}/ready" > /dev/null 2>&1; then
        log_error "Impossible de contacter Loki a ${LOKI_URL}"
        write_report "failed" "[]" '{"error": "connexion impossible"}'
        exit 1
    fi

    local end_epoch
    end_epoch=$(date -d "-${AGE_DAYS} days" +%s 2>/dev/null || date -v-"${AGE_DAYS}"d +%s)

    local item_json
    item_json=$(jq -n --arg sel "$LOKI_LABEL_SELECTOR" --arg end "$end_epoch" \
        '[{selector: $sel, end_epoch: $end}]')

    if [[ "$APPLY" == true ]]; then
        log_warn "Envoi de la requete de suppression a Loki..."
        curl -sf -X POST "${LOKI_URL}/loki/api/v1/delete" \
            --data-urlencode "query=${LOKI_LABEL_SELECTOR}" \
            --data-urlencode "end=${end_epoch}" > /dev/null
        log_info "Requete envoyee. Le compactor Loki traitera la purge en arriere-plan."
        write_report "ok" "$item_json"
    else
        log_info "[DRY-RUN] Requete qui serait envoyee : POST ${LOKI_URL}/loki/api/v1/delete"
        write_report "dry-run" "$item_json"
    fi
}

case "$TARGET" in
    journald) clean_journald ;;
    elasticsearch) clean_elasticsearch ;;
    loki) clean_loki ;;
esac

exit 0
