#!/usr/bin/env bash
# Check ~/git/nixos on every host and optionally sync with origin/main.
#
# Prints a status table with working-tree cleanliness and ahead/behind
# counts vs origin/main for each host. The current machine is checked
# locally; the rest are checked over SSH in parallel.
#
# With --sync, safe actions run automatically (fast-forward pull, push
# of local-ahead commits). Divergent branches prompt before rebasing.
# Dirty working trees are always left untouched.
#
# Usage:
#   ./scripts/sync-nixos-hosts.sh                # status only
#   ./scripts/sync-nixos-hosts.sh --sync         # status, then sync
#   ./scripts/sync-nixos-hosts.sh --sync --yes   # sync without prompting
#
# Exit 0 if every reachable host ends in-sync (or check-only completes).
# Exit 1 if any host was left out of sync (dirty tree, unreachable, or
# user declined a rebase).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOSTS=(airbook latitude otworkstation vm01 log01)
REPO_PATH='~/git/nixos'
SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes)

SYNC=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --sync) SYNC=true ;;
        --yes|-y) ASSUME_YES=true ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CURRENT_HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

# Runs a shell snippet on $host, either locally or via SSH.
run_on() {
    local host="$1"; shift
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        ssh "${SSH_OPTS[@]}" "scott@${host}" "$*"
    fi
}

# Emits: <reachable|unreachable>|<dirty|clean>|<behind>|<ahead>
# on stdout so the caller can parse it. All errors → unreachable.
probe_host() {
    local host="$1"
    local out
    if ! out="$(run_on "$host" "cd ${REPO_PATH} && git fetch --quiet origin 2>&1 >/dev/null; \
        dirty=\$(git status --porcelain | wc -l | tr -d ' '); \
        tree='clean'; [[ \$dirty -gt 0 ]] && tree='dirty'; \
        counts=\$(git rev-list --left-right --count origin/main...HEAD); \
        behind=\$(echo \"\$counts\" | cut -f1); \
        ahead=\$(echo \"\$counts\" | cut -f2); \
        echo \"reachable|\$tree|\$behind|\$ahead\"" 2>/dev/null)"; then
        echo "unreachable|-|-|-"
        return
    fi
    # Take the last non-empty line in case SSH banners leak through.
    echo "$out" | awk 'NF' | tail -n1
}

# Runs probes for every host in parallel; results land in $STATUS[host].
declare -A STATUS
gather_status() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" RETURN
    for host in "${HOSTS[@]}"; do
        (probe_host "$host" > "$tmpdir/$host") &
    done
    wait
    for host in "${HOSTS[@]}"; do
        STATUS[$host]="$(cat "$tmpdir/$host")"
    done
}

print_status_table() {
    printf "%-16s %-12s %-8s %-10s %-10s\n" "HOST" "REACHABLE" "TREE" "BEHIND" "AHEAD"
    printf "%-16s %-12s %-8s %-10s %-10s\n" "----" "---------" "----" "------" "-----"
    for host in "${HOSTS[@]}"; do
        IFS='|' read -r reach tree behind ahead <<<"${STATUS[$host]}"
        local color="$NC" label="$host"
        [[ "$host" == "$CURRENT_HOST" ]] && label="$host (local)"
        if [[ "$reach" == "unreachable" ]]; then
            color="$RED"
        elif [[ "$tree" == "dirty" ]]; then
            color="$YELLOW"
        elif [[ "$behind" != "0" || "$ahead" != "0" ]]; then
            color="$BLUE"
        else
            color="$GREEN"
        fi
        printf "${color}%-16s %-12s %-8s %-10s %-10s${NC}\n" \
            "$label" "$reach" "$tree" "$behind" "$ahead"
    done
}

# Ask a yes/no question unless --yes was passed. Default is no.
confirm() {
    $ASSUME_YES && return 0
    read -rp "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Given a probed host, execute the safe/appropriate sync action.
# Returns 0 if the host ends in sync, 1 otherwise.
sync_host() {
    local host="$1"
    IFS='|' read -r reach tree behind ahead <<<"${STATUS[$host]}"

    if [[ "$reach" != "reachable" ]]; then
        echo -e "${RED}[$host] unreachable, skipping${NC}"
        return 1
    fi
    if [[ "$tree" == "dirty" ]]; then
        echo -e "${YELLOW}[$host] working tree dirty — resolve manually${NC}"
        run_on "$host" "cd ${REPO_PATH} && git status --short" || true
        return 1
    fi
    if [[ "$behind" == "0" && "$ahead" == "0" ]]; then
        echo -e "${GREEN}[$host] already in sync${NC}"
        return 0
    fi

    if [[ "$behind" != "0" && "$ahead" == "0" ]]; then
        echo -e "${BLUE}[$host] pulling $behind commit(s) from origin/main${NC}"
        run_on "$host" "cd ${REPO_PATH} && git pull --ff-only origin main"
        return $?
    fi

    if [[ "$behind" == "0" && "$ahead" != "0" ]]; then
        echo -e "${BLUE}[$host] pushing $ahead commit(s) to origin/main${NC}"
        run_on "$host" "cd ${REPO_PATH} && git push origin main"
        return $?
    fi

    # Diverged: needs rebase + push.
    echo -e "${YELLOW}[$host] diverged: $behind behind, $ahead ahead${NC}"
    if ! confirm "Rebase local commits onto origin/main and push?"; then
        echo -e "${YELLOW}[$host] left diverged${NC}"
        return 1
    fi
    run_on "$host" "cd ${REPO_PATH} && git pull --rebase origin main && git push origin main"
    return $?
}

echo "Probing hosts..."
gather_status
echo
print_status_table
echo

if ! $SYNC; then
    exit 0
fi

echo "Syncing..."
echo
rc=0
for host in "${HOSTS[@]}"; do
    if ! sync_host "$host"; then
        rc=1
    fi
done

echo
echo "Re-probing..."
gather_status
echo
print_status_table
exit $rc
