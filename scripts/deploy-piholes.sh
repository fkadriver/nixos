#!/usr/bin/env bash
# Deploy NixOS updates to pihole02 and pihole01 sequentially (pihole02 first).
# Verifies each Pi is healthy before moving to the next.
#
# pihole02 is HOSTS-ONLY for now (see HOSTS_ONLY below): its micro-USB power
# connector is damaged, so it only gets /etc/hosts (local DNS records) pushed
# live — no rebuild, no reboot — until it's replaced with a Pi 4 (TODO.md §2).
# A pushed hosts file lasts until pihole02's next reboot, which falls back to
# the hosts of its last full deploy; every run of this script re-pushes it.
#
# Build host selection (in order of preference):
#   1. vm01   — always-on server, preferred when available
#   2. localhost — latitude loopback sshd (requires latitude rebuild)
#
# Usage:
#   ./scripts/deploy-piholes.sh                        # deploy both; logs to /tmp/pihole-update_<ts>.log
#   ./scripts/deploy-piholes.sh pihole01               # deploy only pihole01; logs to /tmp/pihole01-update_<ts>.log
#   ./scripts/deploy-piholes.sh pihole02               # deploy only pihole02
#   ./scripts/deploy-piholes.sh --build-host vm01
#   ./scripts/deploy-piholes.sh pihole01 --build-host localhost
#   ./scripts/deploy-piholes.sh --verbose              # also show full nix build logs on screen
#   ./scripts/deploy-piholes.sh --quiet                # no log file, minimal screen output
#   ./scripts/deploy-piholes.sh --check-version        # check if a newer version exists on GitHub
#   ./scripts/deploy-piholes.sh pihole02 --full        # full rebuild+reboot even for a HOSTS_ONLY Pi
#
#   ./scripts/deploy-piholes.sh --build-image                  # build SD images for both Pis
#   ./scripts/deploy-piholes.sh pihole01 --build-image          # build SD image for pihole01 only
#   ./scripts/deploy-piholes.sh pihole02 --build-image --verbose
#   (image builds run locally via QEMU binfmt emulation — no --build-host/target-host involved;
#    see docs/pihole-deployment.md Phase 1)

set -euo pipefail

SCRIPT_VERSION="1.6.0"
SCRIPT_URL="https://raw.githubusercontent.com/fkadriver/nixos/main/scripts/deploy-piholes.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
QUIET=false
FULL=false

# Must match pihole.lockedKernelVersion in each host's default.nix.
# Update both together when intentionally upgrading the kernel.
# pihole01 = Pi 4B (nixos-raspberrypi kernel, prebuilt in its cachix)
# pihole02 = Pi 3B (nixos-hardware kernel)
declare -A LOCKED_KERNEL_VERSIONS
LOCKED_KERNEL_VERSIONS[pihole01]="6.18.59-unstable_20261026"
LOCKED_KERNEL_VERSIONS[pihole02]="6.18.50-stable_20260911"

# Machines that should each have a local copy of built SD images.
# After a successful --build-image, the resulting .img is rsynced to every
# other host in this list (skipping whichever one just built it).
IMAGE_SYNC_HOSTS=("latitude" "vm01")

declare -A PI_DNS
PI_DNS[pihole01]="192.168.10.10"
PI_DNS[pihole02]="192.168.10.11"

declare -A PI_DNS_RETRIES
PI_DNS_RETRIES[pihole01]=5
PI_DNS_RETRIES[pihole02]=15

# Pis that only get their /etc/hosts pushed (no rebuild/reboot) unless --full.
# pihole02: damaged power connector, browns out under load — 2026-11-18 it
# died mid-deploy. Remove once it's replaced (TODO.md §2).
declare -A HOSTS_ONLY
HOSTS_ONLY[pihole02]=true

# pihole02 goes first: it is the canary (only while it gets full deploys). If a change breaks boot (e.g. the
# systemd stage-1 initrd switch in aaf668a), the deploy stops there and
# pihole01 — the primary DNS server — keeps serving untouched.
PIHOLES=("pihole02" "pihole01")

log()  { $QUIET || echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { $QUIET || echo -e "${GREEN}  ✓${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*"; }
warn() { $QUIET || echo -e "${YELLOW}  !${NC} $*"; }

check_new_version() {
    local remote_version
    remote_version=$(curl -fsSL --max-time 5 "$SCRIPT_URL" 2>/dev/null \
        | grep '^SCRIPT_VERSION=' | head -1 | cut -d'"' -f2) || true
    if [[ -z "$remote_version" ]]; then
        warn "Could not fetch remote version (offline or URL changed)"
        return 0
    fi
    if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
        ok "Script is up to date (v${SCRIPT_VERSION})"
    else
        warn "New version available: v${remote_version} (current: v${SCRIPT_VERSION})"
        warn "Update: git pull in ${FLAKE_DIR}"
    fi
}

# Parse arguments
BUILD_HOST=""
BUILD_IMAGE=false
TARGET=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-host) BUILD_HOST="$2"; shift 2 ;;
        --build-image|--image) BUILD_IMAGE=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --quiet|-q) QUIET=true; shift ;;
        --check-version) check_new_version; exit 0 ;;
        --full) FULL=true; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        pihole01|pihole02) TARGET+=("$1"); shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if $VERBOSE && $QUIET; then
    echo "Error: --verbose and --quiet are mutually exclusive" >&2
    exit 1
fi

# Default to both if no target specified
[[ ${#TARGET[@]} -eq 0 ]] && TARGET=("${PIHOLES[@]}")

# Determine log file name based on targets
TS=$(date +%Y%m%d-%H%M%S)
LOGTAG="update"
$BUILD_IMAGE && LOGTAG="image"
if [[ ${#TARGET[@]} -eq 1 ]]; then
    LOGFILE="/tmp/${TARGET[0]}-${LOGTAG}_${TS}.log"
else
    LOGFILE="/tmp/pihole-${LOGTAG}_${TS}.log"
fi

# Set up logging: default and verbose tee to logfile; quiet skips it
if ! $QUIET; then
    exec > >(tee -a "$LOGFILE") 2>&1
fi

# Image builds run entirely on this machine via QEMU binfmt emulation (pi-builder.nix) —
# there's no remote target to deploy to, so the --build-host auto-selection below doesn't apply.
if [[ -z "$BUILD_HOST" ]] && ! $BUILD_IMAGE; then
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

check_kernel_version() {
    local name=$1
    log "Checking kernel version for ${name}..."
    local version
    version=$(nix eval --raw --option builders '' \
        "${FLAKE_DIR}#nixosConfigurations.${name}.config.boot.kernelPackages.kernel.version" \
        2>/dev/null) || { warn "Could not evaluate kernel version (non-fatal)"; return 0; }

    local locked="${LOCKED_KERNEL_VERSIONS[$name]}"
    if [[ "$version" == "$locked" ]]; then
        ok "Kernel ${version} matches locked version"
    else
        echo ""
        warn "━━━ KERNEL VERSION CHANGE DETECTED ━━━"
        warn "  Host:     ${name}"
        warn "  Locked:   ${locked}"
        warn "  Current:  ${version}"
        warn "A full kernel recompile will be required (~2 hours on vm01)."
        warn "Update LOCKED_KERNEL_VERSIONS in this script and"
        warn "pihole.lockedKernelVersion in hosts/${name}/default.nix when ready."
        echo ""
        read -rp "  Proceed with recompile? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || { fail "Aborted."; return 1; }
    fi
}

build_sd_image() {
    local name=$1
    local outlink="${FLAKE_DIR}/result-${name}-sdimage"

    echo ""
    log "━━━ Building SD image for ${name} ━━━"

    check_kernel_version "$name" || return 1

    local build_log_flag=()
    $VERBOSE && build_log_flag=(--print-build-logs)

    if nix build \
        "${FLAKE_DIR}#nixosConfigurations.${name}.config.system.build.sdImage" \
        --out-link "$outlink" \
        --option builders '' \
        "${build_log_flag[@]}"; then
        local img
        img=$(find "${outlink}/sd-image" -maxdepth 1 -name '*.img' | head -1)
        ok "SD image built: ${img}"
        sync_image_to_peers "$name" "$img"
    else
        fail "SD image build failed for ${name}"
        return 1
    fi
}

# Copy a freshly built image out to the other static machines so a card can
# be flashed from either one without re-running the (multi-hour) build.
sync_image_to_peers() {
    local name=$1 img=$2
    local self
    self=$(hostname)

    for peer in "${IMAGE_SYNC_HOSTS[@]}"; do
        [[ "$peer" == "$self" ]] && continue
        log "Syncing ${name} image to ${peer}..."
        local remote_dir="${FLAKE_DIR}/result-${name}-sdimage/sd-image"
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$peer" "mkdir -p '${remote_dir}'" 2>/dev/null \
            && rsync -a --partial "$img" "${peer}:${remote_dir}/"; then
            ok "Synced to ${peer}"
        else
            warn "Could not sync image to ${peer} (non-fatal — copy it manually)"
        fi
    done
}

verify_pi() {
    local name=$1
    local dns_ip=${PI_DNS[$name]}
    local ssh_target="scott@${name}"

    log "Verifying $name..."

    # pihole-ftl starts after bitwarden-secrets-sync → pihole-set-password,
    # so SSH may be available well before the service is ready. Retry for up to 90s.
    local ftl_ok=false
    for i in $(seq 1 18); do
        if ssh "$ssh_target" "systemctl is-active --quiet pihole-ftl" 2>/dev/null; then
            ftl_ok=true; break
        fi
        warn "pihole-ftl not active yet, retrying (${i}/18)..."
        sleep 5
    done
    if $ftl_ok; then
        ok "pihole-ftl is running"
    else
        fail "pihole-ftl is not active after 90s"
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

# Push only /etc/hosts (networking.extraHosts → local DNS records) to a Pi
# and make FTL re-read it. The file is built from the Pi's own config; it's a
# plain text derivation, so this needs no Pi build at all.
push_hosts() {
    local name=$1
    local ssh_target="scott@${name}"
    local dns_ip=${PI_DNS[$name]}

    echo ""
    log "━━━ ${name}: hosts-only update (no rebuild, no reboot) ━━━"

    local hosts
    hosts=$(nix build --no-link --print-out-paths --option builders '' \
        "${FLAKE_DIR}#nixosConfigurations.${name}.config.environment.etc.hosts.source") \
        || { fail "Could not build the hosts file for ${name}"; return 1; }

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" true 2>/dev/null; then
        fail "${name} is not reachable"
        return 1
    fi

    if ssh "$ssh_target" "cat /etc/hosts" 2>/dev/null | cmp -s - "$hosts"; then
        ok "/etc/hosts already current"
    else
        # Write next to it, then rename over the symlink (atomic). FTL answers
        # from /etc/hosts and re-reads it on SIGHUP. Signal its main PID from
        # systemd, not `pihole reloaddns`: that looks for /run/pihole-FTL.pid,
        # which NixOS's FTL doesn't write, and then silently does nothing
        # (still exit 0) — tested 2026-11-18.
        if ssh "$ssh_target" 'sudo tee /etc/hosts.new >/dev/null && sudo chmod 0644 /etc/hosts.new && sudo mv -f /etc/hosts.new /etc/hosts && pid=$(systemctl show -p MainPID --value pihole-ftl) && [ "$pid" -gt 0 ] && sudo kill -HUP "$pid"' < "$hosts"; then
            ok "/etc/hosts pushed and DNS reloaded"
        else
            fail "Could not push /etc/hosts to ${name}"
            return 1
        fi
        ssh "$ssh_target" "cat /etc/hosts" | cmp -s - "$hosts" \
            || { fail "/etc/hosts on ${name} doesn't match after the push"; return 1; }
        warn "Lasts until ${name}'s next reboot (falls back to its last full deploy's hosts)"
    fi

    # Spot-check: every name/IP pair from the file must resolve on the Pi.
    local bad=0 ip host answer
    while read -r ip host _; do
        answer=$(dig "@${dns_ip}" "$host" A +short +time=3 +tries=2 2>/dev/null | tail -1)
        if [[ "$answer" != "$ip" ]]; then
            fail "${host}: expected ${ip}, got '${answer:-nothing}'"
            bad=1
        fi
    done < <(grep -vE '^\s*(#|$)' "$hosts" | grep -vE '^(127\.|::1)' | grep -E '^[0-9]+\.' )
    if [[ $bad -eq 0 ]]; then
        ok "All local DNS records resolve on ${dns_ip}"
    else
        return 1
    fi
}

deploy_pi() {
    local name=$1
    local ssh_target="scott@${name}"

    echo ""
    log "━━━ Deploying ${name} (build: ${BUILD_HOST}) ━━━"

    check_kernel_version "$name" || return 1

    local build_args=()
    [[ "$BUILD_HOST" != "localhost" ]] && build_args=(--build-host "${BUILD_HOST}")

    local rebuild_log_flag=()
    $VERBOSE && rebuild_log_flag=(--print-build-logs)

    if nixos-rebuild boot \
        --flake "${FLAKE_DIR}#${name}" \
        --target-host "$ssh_target" \
        "${build_args[@]}" \
        --option builders '' \
        --sudo \
        "${rebuild_log_flag[@]}"; then
        ok "nixos-rebuild boot completed"
    else
        fail "nixos-rebuild boot failed for ${name}"
        return 1
    fi

    # Keep a GC root on the build machine so the Pi kernel isn't garbage collected.
    # Without this, 'nix.gc.automatic' (every 30d) would remove the compiled kernel
    # and force a full recompile on the next deploy.
    # Use ~/.local/share/nix/gcroots/ (user-writable, respected by nix GC) to avoid
    # needing sudo (latitude requires a sudo password; background deploys would hang).
    local gcroot="${HOME}/.local/share/nix/gcroots/pihole-deploy-${name}"
    mkdir -p "$(dirname "$gcroot")"
    if nix build --option builders '' \
        --out-link "$gcroot" \
        "${FLAKE_DIR}#nixosConfigurations.${name}.config.system.build.toplevel" 2>/dev/null; then
        ok "GC root updated: ${gcroot}"
    else
        warn "Could not create GC root for ${name} (non-fatal)"
    fi

    log "Rebooting ${name}..."
    ssh "$ssh_target" "sudo reboot" 2>/dev/null || true

    # Wait for SSH to drop (reboot hasn't fully started yet)
    sleep 10

    # Poll until SSH comes back
    local waited=10
    local max_wait=120
    while ! ssh -o ConnectTimeout=3 -o BatchMode=yes "$ssh_target" true 2>/dev/null; do
        if [[ $waited -ge $max_wait ]]; then
            fail "${name} did not come back within ${max_wait}s"
            return 1
        fi
        warn "Waiting for ${name} to come back... (${waited}s)"
        sleep 5
        waited=$((waited + 5))
    done
    ok "${name} is back online"

    # Catch "rebooted into the old system": with the old raspberry-pi-nix
    # setup, a kernel change left the old kernel on FIRMWARE and the new
    # system failed to boot (2026-11-17). SSH can still come back on the
    # old generation, so compare what booted with what was just installed.
    local booted installed
    booted=$(ssh "$ssh_target" "readlink -f /run/booted-system" 2>/dev/null || true)
    installed=$(ssh "$ssh_target" "readlink -f /nix/var/nix/profiles/system" 2>/dev/null || true)
    if [[ -n "$booted" && "$booted" == "$installed" ]]; then
        ok "Booted the new generation"
    else
        fail "${name} booted ${booted:-?} but the system profile is ${installed:-?}"
        return 1
    fi

    verify_pi "$name"
}

echo ""
if $BUILD_IMAGE; then
    echo -e "${BLUE}Pi-hole SD image build — $(date)${NC}"
else
    echo -e "${BLUE}Pi-hole deployment — $(date)${NC}"
fi
echo -e "${BLUE}Flake: ${FLAKE_DIR}${NC}"
echo -e "${BLUE}Script version: ${SCRIPT_VERSION}${NC}"
$QUIET || echo -e "${BLUE}Log: ${LOGFILE}${NC}"
$VERBOSE && echo -e "${YELLOW}Verbose mode — full build logs enabled${NC}"
echo ""

check_new_version

if $BUILD_IMAGE; then
    for pi in "${TARGET[@]}"; do
        build_sd_image "$pi" || {
            echo ""
            echo -e "${RED}Image build failed on ${pi} — stopping.${NC}"
            exit 1
        }
    done

    echo ""
    if [[ ${#TARGET[@]} -eq 1 ]]; then
        echo -e "${GREEN}━━━ ${TARGET[0]} SD image built successfully ━━━${NC}"
    else
        echo -e "${GREEN}━━━ All Pi-hole SD images built successfully ━━━${NC}"
    fi
    $QUIET || echo -e "${BLUE}Log saved: ${LOGFILE}${NC}"
    exit 0
fi

verify_build_host

for pi in "${TARGET[@]}"; do
    if [[ "${HOSTS_ONLY[$pi]:-false}" == true ]] && ! $FULL; then
        push_hosts "$pi" || {
            echo ""
            echo -e "${RED}Hosts update failed on ${pi} — stopping.${NC}"
            exit 1
        }
        continue
    fi
    deploy_pi "$pi" || {
        echo ""
        echo -e "${RED}Deployment failed on ${pi} — stopping.${NC}"
        echo "Fix the issue and re-run, or deploy individually:"
        if [[ "$BUILD_HOST" != "localhost" ]]; then
            echo "  nixos-rebuild boot --flake .#${pi} --target-host scott@${pi} --build-host ${BUILD_HOST} --sudo"
        else
            echo "  nixos-rebuild boot --flake .#${pi} --target-host scott@${pi} --sudo"
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
$QUIET || echo -e "${BLUE}Log saved: ${LOGFILE}${NC}"
