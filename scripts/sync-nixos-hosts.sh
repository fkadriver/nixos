#!/usr/bin/env bash
# Check ~/git/nixos on every host and optionally sync with origin/main,
# then optionally apply the NixOS/darwin configuration on each host.
#
# Prints a status table with working-tree cleanliness and ahead/behind
# counts vs origin/main for each host. The current machine is checked
# locally; the rest are checked over SSH in parallel.
#
# With --sync, safe actions run automatically (fast-forward pull, push
# of local-ahead commits). Divergent branches prompt before rebasing.
# Dirty working trees are always left untouched.
#
# With --apply, runs nixos-rebuild (or darwin-rebuild) sequentially on
# each reachable, clean host. Hosts that are behind origin prompt first.
# Remote apply uses an interactive TTY so sudo prompts work.
#
# Usage:
#   ./scripts/sync-nixos-hosts.sh                       # status only
#   ./scripts/sync-nixos-hosts.sh --sync                # status, then sync
#   ./scripts/sync-nixos-hosts.sh --apply               # status, then apply
#   ./scripts/sync-nixos-hosts.sh --sync --apply        # sync, then apply
#   ./scripts/sync-nixos-hosts.sh --sync --apply --yes  # no prompts
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

# Flake config name per host (only needed where it differs from the hostname)
declare -A FLAKE_CONFIG=(
    [airbook]="airbook-darwin"
    [otworkstation]="OTworkstation"
)

SYNC=false
APPLY=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --sync) SYNC=true ;;
        --apply) APPLY=true ;;
        --yes|-y) ASSUME_YES=true ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CURRENT_HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

# Runs a shell snippet on $host, either locally or via SSH (BatchMode).
run_on() {
    local host="$1"; shift
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        ssh "${SSH_OPTS[@]}" "scott@${host}" "$*"
    fi
}

# Like run_on but allocates a TTY so sudo prompts work (used for --apply).
run_on_tty() {
    local host="$1"; shift
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        ssh -t -o ConnectTimeout=5 "scott@${host}" "$*"
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

# Run nixos-rebuild switch (or darwin-rebuild) on a host.
apply_host() {
    local host="$1"
    local config="${FLAKE_CONFIG[$host]:-$host}"
    IFS='|' read -r reach tree behind ahead <<<"${STATUS[$host]}"

    if [[ "$reach" != "reachable" ]]; then
        echo -e "${RED}[$host] unreachable, skipping${NC}"
        return 1
    fi
    if [[ "$tree" == "dirty" ]]; then
        echo -e "${YELLOW}[$host] working tree dirty — resolve before applying${NC}"
        return 1
    fi
    if [[ "$behind" != "0" ]]; then
        echo -e "${YELLOW}[$host] $behind commit(s) behind origin/main${NC}"
        if ! confirm "[$host] Apply with out-of-date repo?"; then
            echo -e "${YELLOW}[$host] skipped${NC}"
            return 1
        fi
    fi

    local rebuild_cmd
    if [[ "$host" == "airbook" ]]; then
        rebuild_cmd="cd ${REPO_PATH} && sudo darwin-rebuild switch --flake .#${config}"
    else
        rebuild_cmd="cd ${REPO_PATH} && sudo nixos-rebuild switch --flake .#${config}"
    fi

    if ! confirm "Apply config on [$host]?"; then
        echo -e "${YELLOW}[$host] skipped${NC}"
        return 0
    fi

    echo -e "${BLUE}[$host] applying...${NC}"
    run_on_tty "$host" "$rebuild_cmd"
}

echo "Probing hosts..."
gather_status
echo
print_status_table
echo

if $SYNC; then
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
    echo

    if [[ $rc -ne 0 ]] && ! $APPLY; then
        exit $rc
    fi
fi

if $APPLY; then
    echo "Applying..."
    echo
    rc=0
    for host in "${HOSTS[@]}"; do
        if ! apply_host "$host"; then
            rc=1
        fi
        echo
    done
    exit $rc
fi

exit 0
