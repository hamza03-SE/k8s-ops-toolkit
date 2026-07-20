#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

STATUS=""
APP_NAME=""
ENVIRONMENT=""
MESSAGE=""

usage() {
    cat << EOF
Usage: $(basename "$0") --status success|failure --app NOM [OPTIONS]

Envoie une notification de deploiement par email (via SMTP).

Variables d'environnement requises (jamais en argument) :
    SMTP_SERVER       Ex: smtp.gmail.com
    SMTP_PORT         Ex: 587
    SMTP_USER         Adresse d'envoi (ex: alertes@example.com)
    SMTP_PASSWORD     Mot de passe ou mot de passe d'application
    EMAIL_TO          Destinataire(s), separes par des virgules

OPTIONS OBLIGATOIRES:
    --status STATUS          Statut du deploiement: success|failure
    --app NAME               Nom de l'application deployee

OPTIONS:
    --env ENVIRONMENT        Environnement concerne (ex: production, staging)
    --message TEXT           Message additionnel (ex: raison d'un echec)
    -h, --help                Affiche cette aide

EXEMPLE:
    export SMTP_SERVER=smtp.gmail.com
    export SMTP_PORT=587
    export SMTP_USER=alertes@example.com
    export SMTP_PASSWORD='motdepasse-application'
    export EMAIL_TO=equipe@example.com

    $(basename "$0") --status success --app mon-app --env production
    $(basename "$0") --status failure --app mon-app --env staging --message "Timeout apres 300s"
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status) STATUS="$2"; shift 2 ;;
        --app) APP_NAME="$2"; shift 2 ;;
        --env) ENVIRONMENT="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            log_error "Option inconnue: $1"
            usage
            exit 1
            ;;
    esac
done

check_dependency curl

# ---- Validations ----
case "$STATUS" in
    success|failure) ;;
    "")
        log_error "--status est obligatoire (success|failure)"
        exit 1
        ;;
    *)
        log_error "Statut invalide: $STATUS (attendu: success|failure)"
        exit 1
        ;;
esac

if [[ -z "$APP_NAME" ]]; then
    log_error "--app est obligatoire"
    exit 1
fi

MISSING=""
[[ -z "${SMTP_SERVER:-}" ]] && MISSING="${MISSING}SMTP_SERVER "
[[ -z "${SMTP_PORT:-}" ]] && MISSING="${MISSING}SMTP_PORT "
[[ -z "${SMTP_USER:-}" ]] && MISSING="${MISSING}SMTP_USER "
[[ -z "${SMTP_PASSWORD:-}" ]] && MISSING="${MISSING}SMTP_PASSWORD "
[[ -z "${EMAIL_TO:-}" ]] && MISSING="${MISSING}EMAIL_TO "

if [[ -n "$MISSING" ]]; then
    log_error "Variables d'environnement manquantes: ${MISSING}"
    exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

if [[ "$STATUS" == "success" ]]; then
    EMOJI="✅"
    TITLE="Deploiement reussi"
else
    EMOJI="❌"
    TITLE="Deploiement echoue"
fi

ENV_LINE=""
[[ -n "$ENVIRONMENT" ]] && ENV_LINE="Environnement : ${ENVIRONMENT}"

MESSAGE_LINE=""
[[ -n "$MESSAGE" ]] && MESSAGE_LINE="Details : ${MESSAGE}"

log_info "Envoi de la notification par email a ${EMAIL_TO}..."

SUBJECT="${EMOJI} ${TITLE} - ${APP_NAME}"
BODY_FILE=$(mktemp)

{
    echo "From: ${SMTP_USER}"
    echo "To: ${EMAIL_TO}"
    echo "Subject: ${SUBJECT}"
    echo ""
    echo "${TITLE}"
    echo "Application : ${APP_NAME}"
    [[ -n "$ENV_LINE" ]] && echo "$ENV_LINE"
    [[ -n "$MESSAGE_LINE" ]] && echo "$MESSAGE_LINE"
    echo "Horodatage : ${TIMESTAMP}"
} > "$BODY_FILE"

if curl -sf --ssl-reqd \
    --url "smtp://${SMTP_SERVER}:${SMTP_PORT}" \
    --mail-from "${SMTP_USER}" \
    --mail-rcpt "${EMAIL_TO}" \
    --user "${SMTP_USER}:${SMTP_PASSWORD}" \
    --upload-file "$BODY_FILE" > /dev/null; then
    rm -f "$BODY_FILE"
    log_info "Email envoye avec succes."
else
    rm -f "$BODY_FILE"
    log_error "Echec de l'envoi de l'email."
    exit 1
fi

exit 0
