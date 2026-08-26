#!/usr/bin/env bash
# Query status from every NixOS host over SSH and print a summary table.
#
# For each host: uptime, Linux version (NixOS/Ubuntu/etc + version number),
# current generation number + build date (NixOS only), kernel version, and
# root filesystem usage. The current machine is checked locally; the rest
# are checked over SSH in parallel.
#
# airbook is excluded — it's macOS/darwin and not reachable via SSH from
# latitude (manual darwin-rebuild only).
#
# nas01-backup is included but isn't NixOS (it's the Ubuntu VM that runs
# IDrive360 — see docs/idrive360.md) — it only reports uptime/kernel/disk,
# not a NixOS version/generation.
#
# Usage:
#   ./scripts/host-status.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTS=(latitude log01 nas01 nas01-backup otworkstation pihole01 pihole02 vm01)

# Non-NixOS hosts: skip nixos-version/generation fields (nixos-rebuild
# doesn't exist there), just report reachability/uptime/kernel/disk.
NON_NIXOS_HOSTS=(nas01-backup)
is_non_nixos() {
    local host="$1"
    for h in "${NON_NIXOS_HOSTS[@]}"; do [[ "$h" == "$host" ]] && return 0; done
    return 1
}
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

# Emits: <reachable|unreachable>|<uptime>|<linux version>|<gen>|<built>|<kernel>|<disk>
# on stdout so the caller can parse it. All errors → unreachable.
# <linux version> is /etc/os-release's PRETTY_NAME (works for NixOS, Ubuntu,
# or anything else — no OS-specific command needed).
# <gen>/<built> come from the current `nixos-rebuild list-generations` entry
# (generation number and its build date/time) — NixOS-only, "-" elsewhere.
probe_host() {
    local host="$1"
    local out
    local common_cmd="\
        uptime=\$(awk '{d=int(\$1/86400); h=int((\$1%86400)/3600); m=int((\$1%3600)/60); \
            if (d>0) printf \"%dd%dh\", d, h; else if (h>0) printf \"%dh%dm\", h, m; else printf \"%dm\", m}' /proc/uptime); \
        osver=\$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'\"' -f2); \
        [[ -z \$osver ]] && osver='-'; \
        kernel=\$(uname -r); \
        disk=\$(df -h / --output=pcent 2>/dev/null | tail -n1 | tr -d ' '); \
        [[ -z \$disk ]] && disk='-';"
    if is_non_nixos "$host"; then
        if ! out="$(run_on "$host" "\
            $common_cmd \
            echo \"reachable|\$uptime|\$osver|-|-|\$kernel|\$disk\"" 2>/dev/null)"; then
            echo "unreachable|-|-|-|-|-|-"
            return
        fi
    elif ! out="$(run_on "$host" "\
        $common_cmd \
        genline=\$(nixos-rebuild list-generations 2>/dev/null | awk '\$NF==\"True\"'); \
        gen=\$(echo \"\$genline\" | awk '{print \$1}'); \
        built=\$(echo \"\$genline\" | awk '{print \$2, \$3}'); \
        [[ -z \$gen ]] && gen='-'; \
        [[ -z \$built || \$built == ' ' ]] && built='-'; \
        echo \"reachable|\$uptime|\$osver|\$gen|\$built|\$kernel|\$disk\"" 2>/dev/null)"; then
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
    printf "%-16s %-10s %-24s %-6s %-20s %-16s %-6s\n" "HOST" "UPTIME" "LINUX VERSION" "GEN" "BUILT" "KERNEL" "DISK"
    printf "%-16s %-10s %-24s %-6s %-20s %-16s %-6s\n" "----" "------" "-------------" "---" "-----" "------" "----"
    for host in "${HOSTS[@]}"; do
        IFS='|' read -r reach uptime osver gen built kernel disk <<<"${STATUS[$host]}"
        local color="$NC" label="$host"
        [[ "$host" == "$CURRENT_HOST" ]] && label="$host (local)"
        if [[ "$reach" == "unreachable" ]]; then
            color="$RED"
            printf "${color}%-16s %-10s${NC}\n" "$label" "unreachable"
            continue
        fi
        printf "${color}%-16s %-10s %-24s %-6s %-20s %-16s %-6s${NC}\n" \
            "$label" "$uptime" "$osver" "$gen" "$built" "$kernel" "$disk"
    done
}

echo "Probing hosts..."
gather_status
echo
print_status_table
