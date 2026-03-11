#!/usr/bin/env bash
# Deploy NixOS updates to pihole01 and pihole02 sequentially.
# Verifies each Pi is healthy before moving to the next.
#
# Prerequisites: latitude must be rebuilt with localhost sshd active:
#   sudo nixos-rebuild switch --flake .#latitude
# Then this script can run as the regular user (no sudo needed here).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -A PI_DNS
PI_DNS[pihole01]="192.168.10.10"
PI_DNS[pihole02]="192.168.10.11"

PIHOLES=("pihole01" "pihole02")

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }

verify_pi() {
    local name=$1
    local dns_ip=${PI_DNS[$name]}
    local ssh_target="scott@${name}"

    log "Verifying $name..."

    # Check pihole-ftl is active
    if ssh "$ssh_target" "systemctl is-active --quiet pihole-ftl" 2>/dev/null; then
        ok "pihole-ftl is running"
    else
        fail "pihole-ftl is not active"
        return 1
    fi

    # Check DNS responds
    if dig "@${dns_ip}" google.com +short +time=5 +tries=2 >/dev/null 2>&1; then
        ok "DNS responding on ${dns_ip}"
    else
        fail "DNS not responding on ${dns_ip}"
        return 1
    fi

    # Check Tailscale serve is up (non-fatal — may take a moment after boot)
    if ssh "$ssh_target" "systemctl is-active --quiet tailscale-serve-pihole" 2>/dev/null; then
        ok "Tailscale serve active"
    else
        warn "tailscale-serve-pihole not active (may still be starting)"
    fi

    return 0
}

deploy_pi() {
    local name=$1
    local ssh_target="scott@${name}"

    echo ""
    log "━━━ Deploying ${name} ━━━"

    if nixos-rebuild switch \
        --flake "${FLAKE_DIR}#${name}" \
        --target-host "$ssh_target" \
        --build-host localhost \
        --use-remote-sudo; then
        ok "nixos-rebuild switch completed"
    else
        fail "nixos-rebuild switch failed for ${name}"
        return 1
    fi

    verify_pi "$name"
}

echo ""
echo -e "${BLUE}Pi-hole deployment — $(date)${NC}"
echo -e "${BLUE}Flake: ${FLAKE_DIR}${NC}"
echo ""

# Check localhost SSH is working before starting
if ! ssh -o ConnectTimeout=3 -o BatchMode=yes localhost true 2>/dev/null; then
    echo -e "${RED}ERROR: ssh localhost failed.${NC}"
    echo "Latitude needs to be rebuilt first to activate localhost sshd:"
    echo "  sudo nixos-rebuild switch --flake .#latitude"
    exit 1
fi
ok "localhost SSH reachable"

for pi in "${PIHOLES[@]}"; do
    deploy_pi "$pi" || {
        echo ""
        echo -e "${RED}Deployment failed on ${pi} — stopping.${NC}"
        echo "Fix the issue and re-run, or deploy individually:"
        echo "  nixos-rebuild switch --flake .#${pi} --target-host scott@${pi} --build-host localhost --use-remote-sudo"
        exit 1
    }
done

echo ""
echo -e "${GREEN}━━━ All Pi-holes updated successfully ━━━${NC}"
