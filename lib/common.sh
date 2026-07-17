#!/usr/bin/env bash
if [[ -t 1]]; then
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_YELLOW='\033[1;33m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_RESET='\033[0m'
else
    readonly COLOR_RED=''
    readonly COLOR_YELLOW=''
    readonly COLOR_GREEN=''
    readonly COLOR_RESET=''
fi

log_info(){
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"
}

log_warn(){
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error(){
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

check_dependency(){
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "La commande '$cmd' est requise mais introuvable. Installe-la avant de continuer."
        exit 1
    fi
}

