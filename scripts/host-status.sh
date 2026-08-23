#!/usr/bin/env bash
# Query status from every NixOS host over SSH and print a summary table.
#
# For each host: uptime, NixOS version, current generation number + build
# date, kernel version, and root filesystem usage. The current machine is
# checked locally; the rest are checked over SSH in parallel.
#
# airbook is excluded — it's macOS/darwin and not reachable via SSH from
# latitude (manual darwin-rebuild only).
#
# Usage:
#   ./scripts/host-status.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTS=(latitude log01 nas01 otworkstation pihole01 pihole02 vm01)
SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes)

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CURRENT_HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

# Runs a shell snippet on $host, either locally or via Tailscale SSH.
#
# `tailscale ssh` is used instead of plain `ssh` so host-key verification goes
# through the Tailscale coordination server rather than local known_hosts —
# no manual key acceptance needed for new/reinstalled hosts. It's a wrapper
# around the system ssh: any ssh options must come *after* the host, where
# tailscale forwards them to the underlying ssh command.
run_on() {
    local host="$1"; shift
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        tailscale ssh "scott@${host}" "${SSH_OPTS[@]}" "$*"
    fi
}

# Emits: <reachable|unreachable>|<uptime>|<nixos version>|<gen>|<built>|<kernel>|<disk>
# on stdout so the caller can parse it. All errors → unreachable.
# <gen>/<built> come from the current `nixos-rebuild list-generations` entry
# (generation number and its build date/time).
probe_host() {
    local host="$1"
    local out
    if ! out="$(run_on "$host" "\
        uptime=\$(awk '{d=int(\$1/86400); h=int((\$1%86400)/3600); m=int((\$1%3600)/60); \
            if (d>0) printf \"%dd%dh\", d, h; else if (h>0) printf \"%dh%dm\", h, m; else printf \"%dm\", m}' /proc/uptime); \
        nver=\$(nixos-version | awk '{print \$1}'); \
        genline=\$(nixos-rebuild list-generations 2>/dev/null | awk '\$NF==\"True\"'); \
        gen=\$(echo \"\$genline\" | awk '{print \$1}'); \
        built=\$(echo \"\$genline\" | awk '{print \$2, \$3}'); \
        kernel=\$(uname -r); \
        disk=\$(df -h / --output=pcent 2>/dev/null | tail -n1 | tr -d ' '); \
        [[ -z \$gen ]] && gen='-'; \
        [[ -z \$built || \$built == ' ' ]] && built='-'; \
        [[ -z \$disk ]] && disk='-'; \
        echo \"reachable|\$uptime|\$nver|\$gen|\$built|\$kernel|\$disk\"" 2>/dev/null)"; then
        echo "unreachable|-|-|-|-|-|-"
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
    printf "%-16s %-10s %-24s %-6s %-20s %-16s %-6s\n" "HOST" "UPTIME" "NIXOS VERSION" "GEN" "BUILT" "KERNEL" "DISK"
    printf "%-16s %-10s %-24s %-6s %-20s %-16s %-6s\n" "----" "------" "-------------" "---" "-----" "------" "----"
    for host in "${HOSTS[@]}"; do
        IFS='|' read -r reach uptime nver gen built kernel disk <<<"${STATUS[$host]}"
        local color="$NC" label="$host"
        [[ "$host" == "$CURRENT_HOST" ]] && label="$host (local)"
        if [[ "$reach" == "unreachable" ]]; then
            color="$RED"
            printf "${color}%-16s %-10s${NC}\n" "$label" "unreachable"
            continue
        fi
        printf "${color}%-16s %-10s %-24s %-6s %-20s %-16s %-6s${NC}\n" \
            "$label" "$uptime" "$nver" "$gen" "$built" "$kernel" "$disk"
    done
}

echo "Probing hosts..."
gather_status
echo
print_status_table
