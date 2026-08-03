#!/usr/bin/env bash
# Check for firmware updates (via fwupd) on every host that has the
# fwupd module enabled, and prompt to apply them.
#
# For each host, refreshes LVFS metadata and runs `fwupdmgr get-updates`
# (locally for the current machine, over an interactive SSH session for
# the rest, so sudo password prompts work). If you choose to apply,
# `fwupdmgr update` itself prompts per-device before installing anything.
#
# Usage:
#   ./scripts/check-fw-updates.sh          # check each host, prompt to apply
#   ./scripts/check-fw-updates.sh --yes    # skip the per-host apply prompt
#                                           # (fwupdmgr's own per-device
#                                           # prompts still apply)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOSTS=(latitude otworkstation vm01 nas01 log01)

# SSH hostname per host (only needed where it differs from the lowercase name)
declare -A SSH_HOST=(
    [otworkstation]="OTworkstation"
)

ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CURRENT_HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

# Runs a command on $host with a TTY, either locally or over SSH, so
# sudo password prompts and fwupdmgr's interactive confirmations work.
run_on_tty() {
    local host="$1"; shift
    local sshhost="${SSH_HOST[$host]:-$host}"
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        ssh -t -o ConnectTimeout=5 "scott@${sshhost}" "$*"
    fi
}

confirm() {
    $ASSUME_YES && return 0
    read -rp "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

check_host() {
    local host="$1"
    echo -e "${BLUE}=== $host ===${NC}"

    if ! run_on_tty "$host" "sudo fwupdmgr refresh --force; sudo fwupdmgr get-updates"; then
        echo -e "${YELLOW}[$host] no updates available (or host unreachable — see output above)${NC}"
    fi

    if confirm "[$host] Run fwupdmgr update now?"; then
        run_on_tty "$host" "sudo fwupdmgr update"
    fi
    echo
}

for host in "${HOSTS[@]}"; do
    check_host "$host"
done
