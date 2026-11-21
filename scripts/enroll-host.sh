#!/usr/bin/env bash
# Enroll a freshly installed <host>-bootstrap system and build its full config.
# Run on latitude (or any machine with the sops admin age key and Tailscale
# SSH to the fleet). See docs/installing.md for the whole staged install.
#
# Prerequisites: the host was installed from the ISO as <host>-bootstrap and
# `bootstrap-join` has been run on it (joined Tailscale as tag:device).
#
# Steps:
#   1. Read the host's sops age public key (published by bootstrap.nix at
#      /var/lib/sops-nix/key.pub) and its /etc/ssh ed25519 host key.
#   2. Add/replace the age key in .sops.yaml, `sops updatekeys`, and pin the
#      host key in modules/distributed-builds.nix (if the host is a peer).
#   3. Commit and push (prompts unless --yes).
#   4. On the host: clone/pull ~/git/nixos, rebuild <host>-bootstrap (sops now
#      decrypts, so Bitwarden delivers id_ed25519_legacy, which peer
#      substitution needs), then rebuild the full <host> config, which now
#      fetches from the nas01 cache proxy and fleet peers.
#
# Refuses to build the full config if its fileSystems don't match the disko
# layout the bootstrap installed (e.g. /boot still mounted by an old UUID),
# since that system wouldn't boot.
#
# Usage:
#   scripts/enroll-host.sh <host> [--yes] [--no-build]
#     <host>      flake config name (airbook, OTworkstation, vm01, ...)
#     --yes       don't prompt before committing/pushing
#     --no-build  stop after pushing the key changes (steps 1-3)

set -euo pipefail

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$0"; }

HOST="" ASSUME_YES=false BUILD=true
for arg in "$@"; do
    case "$arg" in
        --yes) ASSUME_YES=true ;;
        --no-build) BUILD=false ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) [[ -z "$HOST" ]] && HOST="$arg" || { echo "Only one host" >&2; exit 2; } ;;
    esac
done
[[ -n "$HOST" ]] || { usage; exit 2; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
SSH_HOST="${HOST,,}"   # Tailscale names are lowercase (OTworkstation -> otworkstation)
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

say()  { echo -e "\033[0;34m==> $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN: $*\033[0m" >&2; }
die()  { echo -e "\033[0;31mERROR: $*\033[0m" >&2; exit 1; }
remote()     { tailscale ssh "scott@${SSH_HOST}" -o ConnectTimeout=10 "$*"; }
remote_tty() { tailscale ssh "scott@${SSH_HOST}" -t -o ConnectTimeout=10 "$*"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }

# --- preflight ---------------------------------------------------------------
[[ -f "$SOPS_AGE_KEY_FILE" ]] || die "sops admin key not found at $SOPS_AGE_KEY_FILE"
[[ -z "$(git status --porcelain)" ]] || die "working tree not clean"
git pull -q --ff-only || die "could not fast-forward main"

nix eval --raw ".#nixosConfigurations.${HOST}-bootstrap.config.system.name" >/dev/null 2>&1 \
    || die "no nixosConfigurations.${HOST}-bootstrap (add it to bootstrapHardware in flake.nix)"

if $BUILD; then
    say "Checking ${HOST}'s full config mounts the disko layout"
    fs=$(nix eval --json ".#nixosConfigurations.${HOST}.config.fileSystems" \
        --apply 'f: { root = f."/".device; boot = f."/boot".device; }' 2>/dev/null) \
        || die "could not evaluate ${HOST}'s fileSystems"
    root=$(jq -r .root <<<"$fs"); boot=$(jq -r .boot <<<"$fs")
    [[ "$root" == "/dev/mapper/main_vg-root" && "$boot" == "/dev/disk/by-label/NIXBOOT" ]] \
        || die "${HOST}'s hardware config mounts / from '$root' and /boot from '$boot'.
       The bootstrap installed the disko layout (/dev/mapper/main_vg-root,
       /dev/disk/by-label/NIXBOOT); fix hosts/${HOST}'s hardware config first,
       or rerun with --no-build."
fi

# --- 1. read keys from the host ----------------------------------------------
say "Reading keys from ${SSH_HOST} over Tailscale SSH"
actual=$(remote hostname) || die "can't reach ${SSH_HOST} — did bootstrap-join finish?"
[[ "$actual" == "$HOST" ]] || die "${SSH_HOST} reports hostname '$actual', expected '$HOST'"
AGE_PUB=$(remote cat /var/lib/sops-nix/key.pub | tr -d '[:space:]')
[[ "$AGE_PUB" =~ ^age1[0-9a-z]{58}$ ]] || die "bad age public key from host: '$AGE_PUB'"
HOST_KEY=$(remote cat /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $1" "$2}')
[[ "$HOST_KEY" =~ ^ssh-ed25519\ AAAA ]] || die "bad ssh host key from host: '$HOST_KEY'"
echo "  age key:  $AGE_PUB"
echo "  host key: $HOST_KEY"

# --- 2. update .sops.yaml + secrets, pin host key -----------------------------
say "Updating .sops.yaml and distributed-builds.nix"
python3 - "$HOST" "$AGE_PUB" "$HOST_KEY" <<'EOF'
import re, sys
host, age, hostkey = sys.argv[1:]
p = '.sops.yaml'; s = open(p).read()
anchor = re.compile(rf'^(\s*- &{re.escape(host)} )age1\S+', re.M)
if anchor.search(s):
    s = anchor.sub(rf'\g<1>{age}', s, count=1)
else:
    s = s.replace('\ncreation_rules:', f'\n  # {host} (enrolled by scripts/enroll-host.sh)\n  - &{host} {age}\n\ncreation_rules:', 1)
    # add the alias to the age list of the secrets.yaml rule (after its last alias)
    m = list(re.finditer(r'^([ \t]*)- \*\S+[ \t]*$', s, re.M))
    if not m: sys.exit('could not find creation_rules age list in .sops.yaml')
    last = m[-1]
    s = s[:last.end()] + f'\n{last.group(1)}- *{host}' + s[last.end():]
open(p, 'w').write(s)

p = 'modules/distributed-builds.nix'; s = open(p).read()
key = re.compile(rf'^(\s*{re.escape(host)}\s*=\s*")ssh-ed25519 [A-Za-z0-9+/=]+(";)', re.M)
if key.search(s):
    s = key.sub(rf'\g<1>{hostkey}\g<2>', s, count=1)
    open(p, 'w').write(s)
else:
    print(f'NOTE: {host} is not a distributed-builds peer; host key not pinned', file=sys.stderr)
EOF
sops updatekeys -y secrets/secrets.yaml >/dev/null

if [[ -z "$(git status --porcelain)" ]]; then
    say "Keys already enrolled — nothing to commit"
else
    git --no-pager diff --stat
    confirm "Commit and push these changes?" || die "aborted; changes left uncommitted"
    git add .sops.yaml secrets/secrets.yaml modules/distributed-builds.nix
    git commit -q -m "enroll ${HOST}: add sops age key and pin ssh host key

Generated by scripts/enroll-host.sh."
    git push -q
    say "Pushed $(git rev-parse --short HEAD)"
fi

$BUILD || { say "Done (--no-build). Build later with: scripts/enroll-host.sh ${HOST}"; exit 0; }

# --- 4. build on the host -----------------------------------------------------
say "Updating ~/git/nixos on ${SSH_HOST}"
remote "set -e; [ -d ~/git/nixos/.git ] || git clone -q https://github.com/fkadriver/nixos ~/git/nixos; \
    cd ~/git/nixos && git fetch -q origin && git checkout -q main && git merge -q --ff-only origin/main && git log --oneline -1"

say "Pass 1: ${HOST}-bootstrap (secrets now decrypt; Bitwarden delivers SSH keys)"
remote_tty "cd ~/git/nixos && sudo nixos-rebuild switch --flake .#${HOST}-bootstrap" \
    || warn "bootstrap rebuild reported errors; checking whether the keys arrived anyway"
for _ in $(seq 1 30); do
    remote "test -s ~/.ssh/id_ed25519_legacy" 2>/dev/null && break
    sleep 5
done
remote "test -s ~/.ssh/id_ed25519_legacy" \
    || die "id_ed25519_legacy never arrived; check 'systemctl status bitwarden-secrets-sync' on ${SSH_HOST}"

say "Pass 2: full ${HOST} config (substitutes from nas01 proxy + fleet peers)"
remote_tty "cd ~/git/nixos && sudo nixos-rebuild switch --flake .#${HOST}" \
    || die "full rebuild failed; fix and rerun: scripts/enroll-host.sh ${HOST}"

say "${HOST} is on its full config. Reboot it to load the new kernel/initrd if they changed."
echo "Other hosts pick up the pinned host key on their next rebuild (nix-sync --apply)."
