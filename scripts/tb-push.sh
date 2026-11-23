#!/usr/bin/env bash
# Copy the whole Thunderbird profile directory (~/.thunderbird) from one
# daily-driver host to one or more others.
#
# Thunderbird account setup (accounts, identities, filters, address books,
# saved passwords + OAuth tokens) lives only in the profile, not in Nix —
# Nix just installs Thunderbird (programs.thunderbird in daily-driver.nix).
# A new or rebuilt host gets its profile copied over once with this script
# (or restored from borg, which backs up /home), instead of redoing the setup.
#
# Prompts for the source host and the destination host(s), then checks that
# Thunderbird is NOT running on any of them. Copying a live profile corrupts
# its SQLite databases, so an unreachable host (e.g. a sleeping laptop) also
# blocks the push, because nothing can be checked there. Each destination's
# existing ~/.thunderbird is moved aside to ~/.thunderbird.pre-tb-push-<time>
# rather than deleted, so it stays available as a fallback.
#
# All transfers use Tailscale SSH, same as the other fleet scripts.
#
# Usage:
#   tb-push            (or ./scripts/tb-push.sh)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Daily-driver NixOS hosts (those importing modules/daily-driver.nix).
HOSTS=(latitude airbook)

SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes)
CURRENT_HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"

# Excluded from the copy: lock files (would make the copy look "in use"),
# caches that are rebuilt, and crash/telemetry leftovers.
EXCLUDES=(
    --exclude 'lock' --exclude '.parentlock'
    --exclude 'cache2' --exclude 'startupCache'
    --exclude 'Crash Reports' --exclude 'minidumps'
    --exclude 'Pending Pings' --exclude 'saved-telemetry-pings'
)

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Runs a shell snippet on $host, either locally or via Tailscale SSH (ssh
# options go *after* the host, where tailscale forwards them to ssh).
run_on() {
    local host="$1"; shift
    if [[ "$host" == "$CURRENT_HOST" ]]; then
        bash -c "$*"
    else
        tailscale ssh "scott@${host}" "${SSH_OPTS[@]}" "$*"
    fi
}

# Prints "running", "stopped", or "unreachable" for $host.
# The [b] bracket keeps the pattern from matching the bash -c running it.
# Matches both the NixOS wrapper (.thunderbird-wrapped) and a plain binary.
tb_state() {
    local out
    if out=$(run_on "$1" "pgrep -u \"\$(id -u)\" -f '[b]in/\\.?thunderbird' >/dev/null && echo running || echo stopped" 2>/dev/null); then
        echo "$out"
    else
        echo "unreachable"
    fi
}

# --- Pick source -----------------------------------------------------------
echo "Daily-driver hosts:"
for i in "${!HOSTS[@]}"; do
    mark=""; [[ "${HOSTS[$i]}" == "$CURRENT_HOST" ]] && mark="  (this host)"
    echo "  $((i + 1))) ${HOSTS[$i]}${mark}"
done

default_src=""
for h in "${HOSTS[@]}"; do [[ "$h" == "$CURRENT_HOST" ]] && default_src="$h"; done

pick_host() {  # $1 = number or name → echoes host name, or returns 1
    local sel="$1"
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#HOSTS[@]} )); then
        echo "${HOSTS[$((sel - 1))]}"; return 0
    fi
    for h in "${HOSTS[@]}"; do [[ "$h" == "$sel" ]] && { echo "$h"; return 0; }; done
    return 1
}

while :; do
    read -rp "Source host${default_src:+ [$default_src]}: " sel
    sel="${sel:-$default_src}"
    SRC=$(pick_host "$sel") && break
    echo -e "${RED}Unknown host: '$sel'${NC}"
done

# --- Pick destination(s) ----------------------------------------------------
OTHERS=()
for h in "${HOSTS[@]}"; do [[ "$h" != "$SRC" ]] && OTHERS+=("$h"); done
if (( ${#OTHERS[@]} == 0 )); then
    echo -e "${RED}No other hosts to push to.${NC}" >&2; exit 1
fi

while :; do
    read -rp "Destination host(s), space-separated [${OTHERS[*]}]: " -a sels
    (( ${#sels[@]} )) || sels=("${OTHERS[@]}")
    DESTS=(); ok=1
    for s in "${sels[@]}"; do
        if ! d=$(pick_host "$s"); then
            echo -e "${RED}Unknown host: '$s'${NC}"; ok=0; break
        fi
        if [[ "$d" == "$SRC" ]]; then
            echo -e "${RED}$d is the source; it can't also be a destination.${NC}"; ok=0; break
        fi
        [[ " ${DESTS[*]} " == *" $d "* ]] || DESTS+=("$d")
    done
    (( ok )) && break
done

# --- Confirm Thunderbird is down everywhere ----------------------------------
ALL=("$SRC" "${DESTS[@]}")
while :; do
    echo
    echo "Checking Thunderbird on: ${ALL[*]}"
    blocked=0
    for h in "${ALL[@]}"; do
        state=$(tb_state "$h")
        case "$state" in
            stopped)     echo -e "  ${GREEN}✓${NC} $h: not running" ;;
            running)     echo -e "  ${RED}✗${NC} $h: Thunderbird is RUNNING. Quit it there"; blocked=1 ;;
            *)           echo -e "  ${RED}✗${NC} $h: unreachable, can't confirm (asleep? off the tailnet?)"; blocked=1 ;;
        esac
    done
    (( blocked )) || break
    read -rp "Fix the above, then press Enter to re-check (q to abort): " ans
    [[ "$ans" == q* ]] && { echo "Aborted."; exit 1; }
done

# Source must actually have a profile.
if ! run_on "$SRC" 'test -f ~/.thunderbird/profiles.ini'; then
    echo -e "${RED}$SRC has no ~/.thunderbird/profiles.ini; nothing to push.${NC}" >&2
    exit 1
fi

# --- Options + final confirmation --------------------------------------------
sizes=$(run_on "$SRC" 'du -sh ~/.thunderbird 2>/dev/null | cut -f1; du -shc ~/.thunderbird/*/ImapMail 2>/dev/null | tail -1 | cut -f1')
total_size=$(sed -n 1p <<<"$sizes"); imap_size=$(sed -n 2p <<<"$sizes")

echo
echo "Profile on $SRC: ${total_size:-?} total, of which ${imap_size:-0} is cached IMAP mail."
read -rp "Include cached IMAP mail? (No = destinations re-download it from the server) [Y/n]: " ans
if [[ "$ans" == [nN]* ]]; then
    EXCLUDES+=(--exclude 'ImapMail')
fi

TS=$(date +%Y%m%d-%H%M%S)
echo
echo -e "${YELLOW}About to copy ~/.thunderbird: $SRC → ${DESTS[*]}${NC}"
echo "  Each destination's current ~/.thunderbird is moved to ~/.thunderbird.pre-tb-push-$TS"
read -rp "Proceed? [y/N]: " ans
[[ "$ans" == [yY]* ]] || { echo "Aborted."; exit 1; }

# --- Push --------------------------------------------------------------------
# rsync runs on this host when it's an endpoint (push or pull), otherwise on
# the source. The remote side is reached with `-e "tailscale ssh"` and no
# user@ (rsync would turn that into `-l user`, which tailscale ssh rejects
# before the host). Same username everywhere, so it defaults correctly.
rc=0
for dest in "${DESTS[@]}"; do
    echo
    echo "=== $SRC → $dest ==="

    # Re-check right before touching anything, in case Thunderbird was started
    # since the check above.
    for h in "$SRC" "$dest"; do
        if [[ "$(tb_state "$h")" != "stopped" ]]; then
            echo -e "${RED}Thunderbird is running (or $h is unreachable) again; skipping $dest.${NC}"
            rc=1; continue 2
        fi
    done

    run_on "$dest" "if [ -e ~/.thunderbird ]; then mv ~/.thunderbird ~/.thunderbird.pre-tb-push-$TS && echo 'Moved old profile to ~/.thunderbird.pre-tb-push-$TS'; fi"

    rsync_args=(-a --info=progress2 "${EXCLUDES[@]}" -e "tailscale ssh")
    ok=1
    if [[ "$SRC" == "$CURRENT_HOST" ]]; then
        rsync "${rsync_args[@]}" ~/.thunderbird/ "${dest}:.thunderbird/" || ok=0
    elif [[ "$dest" == "$CURRENT_HOST" ]]; then
        rsync "${rsync_args[@]}" "${SRC}:.thunderbird/" ~/.thunderbird/ || ok=0
    else
        run_on "$SRC" "rsync $(printf '%q ' "${rsync_args[@]}") ~/.thunderbird/ $(printf '%q' "${dest}:.thunderbird/")" || ok=0
    fi

    if (( ok )); then
        echo -e "${GREEN}✓ $dest done${NC}"
    else
        rc=1
        echo -e "${RED}✗ copy to $dest failed. Old profile is still at ~/.thunderbird.pre-tb-push-$TS on $dest${NC}"
    fi
done

echo
if (( rc == 0 )); then
    echo -e "${GREEN}All done.${NC} Start Thunderbird on the destination(s); if Gmail/iCloud ask to sign in, do it once."
    echo "Once it looks right, the ~/.thunderbird.pre-tb-push-$TS backups can be deleted."
fi
exit $rc
