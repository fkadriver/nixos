#!/usr/bin/env bash
# Deploy NixOS updates to pihole01 and pihole02 sequentially.
# Verifies each Pi is healthy before moving to the next.
#
# Build host selection (in order of preference):
#   1. vm01   — always-on server, preferred when available
#   2. localhost — latitude loopback sshd (requires latitude rebuild)
#
# Usage:
#   ./scripts/deploy-piholes.sh                        # deploy both, auto-select build host
#   ./scripts/deploy-piholes.sh pihole01               # deploy only pihole01
#   ./scripts/deploy-piholes.sh pihole02               # deploy only pihole02
#   ./scripts/deploy-piholes.sh --build-host vm01
#   ./scripts/deploy-piholes.sh pihole01 --build-host localhost

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

declare -A PI_DNS_RETRIES
PI_DNS_RETRIES[pihole01]=5
PI_DNS_RETRIES[pihole02]=15

PIHOLES=("pihole01" "pihole02")

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }

# Parse arguments
BUILD_HOST=""
TARGET=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-host) BUILD_HOST="$2"; shift 2 ;;
        pihole01|pihole02) TARGET+=("$1"); shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Default to both if no target specified
[[ ${#TARGET[@]} -eq 0 ]] && TARGET=("${PIHOLES[@]}")

# Auto-select build host if not specified
if [[ -z "$BUILD_HOST" ]]; then
    if [[ "$(hostname)" == "vm01" ]]; then
        # Running on vm01 itself — build locally (omit --build-host to avoid SSH to localhost)
        BUILD_HOST="localhost"
    elif ssh -o ConnectTimeout=3 -o BatchMode=yes scott@vm01 true 2>/dev/null; then
        BUILD_HOST="scott@vm01"
    elif ssh -o ConnectTimeout=3 -o BatchMode=yes localhost true 2>/dev/null; then
        BUILD_HOST="localhost"
    else
        echo -e "${RED}ERROR: No build host available.${NC}"
        echo "Neither vm01 nor localhost SSH is reachable. Options:"
        echo "  • Rebuild latitude:  sudo nixos-rebuild switch --flake .#latitude"
        echo "  • Ensure vm01 is up: ssh scott@vm01"
        exit 1
    fi
fi

verify_build_host() {
    log "Verifying build host: ${BUILD_HOST}"
    if [[ "$BUILD_HOST" == "localhost" ]]; then
        ok "Build host is local machine"
        return 0
    fi
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${BUILD_HOST}" true 2>/dev/null; then
        ok "Build host ${BUILD_HOST} reachable"
    else
        fail "Build host ${BUILD_HOST} not reachable"
        exit 1
    fi
}

verify_pi() {
    local name=$1
    local dns_ip=${PI_DNS[$name]}
    local ssh_target="scott@${name}"

    log "Verifying $name..."

    if ssh "$ssh_target" "systemctl is-active --quiet pihole-ftl" 2>/dev/null; then
        ok "pihole-ftl is running"
    else
        fail "pihole-ftl is not active"
        return 1
    fi

    local dns_ok=false
    local max_retries=${PI_DNS_RETRIES[$name]}
    for i in $(seq 1 "$max_retries"); do
        if dig "@${dns_ip}" google.com +short +time=5 +tries=1 >/dev/null 2>&1; then
            dns_ok=true; break
        fi
        [[ $i -lt $max_retries ]] && { warn "DNS not ready yet, retrying (${i}/${max_retries})..."; sleep 5; }
    done
    if $dns_ok; then
        ok "DNS responding on ${dns_ip}"
    else
        fail "DNS not responding on ${dns_ip}"
        return 1
    fi

    # Non-fatal: Tailscale serve may still be starting up
    if ssh "$ssh_target" "systemctl is-active --quiet tailscale-serve-pihole" 2>/dev/null; then
        ok "Tailscale serve active"
    else
        warn "tailscale-serve-pihole not active yet (may still be starting)"
    fi

    return 0
}

deploy_pi() {
    local name=$1
    local ssh_target="scott@${name}"

    echo ""
    log "━━━ Deploying ${name} (build: ${BUILD_HOST}) ━━━"

    local build_args=()
    [[ "$BUILD_HOST" != "localhost" ]] && build_args=(--build-host "${BUILD_HOST}")

    if nixos-rebuild switch \
        --flake "${FLAKE_DIR}#${name}" \
        --target-host "$ssh_target" \
        "${build_args[@]}" \
        --sudo \
        --print-build-logs; then
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

verify_build_host

for pi in "${TARGET[@]}"; do
    deploy_pi "$pi" || {
        echo ""
        echo -e "${RED}Deployment failed on ${pi} — stopping.${NC}"
        echo "Fix the issue and re-run, or deploy individually:"
        if [[ "$BUILD_HOST" != "localhost" ]]; then
            echo "  nixos-rebuild switch --flake .#${pi} --target-host scott@${pi} --build-host ${BUILD_HOST} --sudo"
        else
            echo "  nixos-rebuild switch --flake .#${pi} --target-host scott@${pi} --sudo"
        fi
        exit 1
    }
done

echo ""
if [[ ${#TARGET[@]} -eq 1 ]]; then
    echo -e "${GREEN}━━━ ${TARGET[0]} updated successfully ━━━${NC}"
else
    echo -e "${GREEN}━━━ All Pi-holes updated successfully ━━━${NC}"
fi
