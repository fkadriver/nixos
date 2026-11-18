#!/usr/bin/env bash
# Carry a Pi's identity onto a freshly flashed SD card, before its first boot,
# so the new card comes up as the same machine instead of a stranger:
#
#   /var/lib/sops-nix/key.txt   age key     -> secrets decrypt, no .sops.yaml change
#   /etc/ssh/ssh_host_*         host keys   -> no known_hosts warnings; the ed25519
#                                              key is also a sops-nix age identity
#   /var/lib/tailscale/         node state  -> same tailnet node + *.ts.net name
#
# The state is pulled live over SSH from the running Pi (old card) and
# written into the new card's NIXOS_SD root partition, mounted here.
# Only one of the two cards may be online afterwards: they share a Tailscale
# identity. Swap cards; don't run both.
#
# Usage (on latitude, card in the reader, image already flashed):
#   ./scripts/seed-pihole-card.sh pihole01 /dev/mmcblk0
#
# Needs local sudo (mount, root-owned files) and passwordless sudo on the Pi
# (pihole hosts set security.sudo.wheelNeedsPassword = false).

set -euo pipefail

HOST=${1:?usage: $0 <pihole01|pihole02> <card-device, e.g. /dev/mmcblk0>}
DEV=${2:?usage: $0 <pihole01|pihole02> <card-device, e.g. /dev/mmcblk0>}

case "$HOST" in pihole01|pihole02) ;; *) echo "Unknown host: $HOST" >&2; exit 1 ;; esac

[[ -b "$DEV" ]] || { echo "$DEV is not a block device" >&2; exit 1; }
# mmcblk0 -> mmcblk0p2, sdb -> sdb2
if [[ "$DEV" =~ [0-9]$ ]]; then ROOTPART="${DEV}p2"; else ROOTPART="${DEV}2"; fi

label=$(lsblk -no LABEL "$ROOTPART" 2>/dev/null || true)
if [[ "$label" != "NIXOS_SD" ]]; then
    echo "$ROOTPART has label '${label}', expected NIXOS_SD — is the image flashed to $DEV?" >&2
    exit 1
fi
if findmnt -rno TARGET "$ROOTPART" >/dev/null; then
    echo "$ROOTPART is already mounted; unmount it first." >&2
    exit 1
fi

SSH_TARGET="scott@${HOST}"
ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_TARGET" true \
    || { echo "Cannot reach ${SSH_TARGET} (the old card must still be running)" >&2; exit 1; }

MNT=$(mktemp -d "/tmp/seed-${HOST}.XXXXXX")
cleanup() { sudo umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

sudo mount "$ROOTPART" "$MNT"

echo "Copying identity from ${HOST} -> ${ROOTPART}..."
# The glob expands on the Pi. --numeric-owner keeps uid/gid as on the Pi
# (all of these are root-owned there) instead of remapping by local names.
ssh "$SSH_TARGET" \
    'sudo tar -C / --numeric-owner -cpf - var/lib/sops-nix/key.txt etc/ssh/ssh_host_* var/lib/tailscale' \
    | sudo tar -C "$MNT" --numeric-owner -xpf -

sudo chmod 0700 "$MNT/var/lib/sops-nix" "$MNT/var/lib/tailscale"
sudo chmod 0600 "$MNT/var/lib/sops-nix/key.txt"

echo "Seeded:"
sudo ls -l "$MNT/var/lib/sops-nix" "$MNT/var/lib/tailscale" "$MNT"/etc/ssh/ssh_host_*
echo "age key: $(sudo grep -m1 'public key' "$MNT/var/lib/sops-nix/key.txt")"
echo
echo "Done. Next: shut down ${HOST} (old card), swap in this card, power on."
