#!/bin/bash
# Restore the nas01-backup VM disk (+ cloud-init ISO) from the local Borg
# repo at /pool/borg/nas01. Use after nas01's OS SSD fails and is reinstalled
# from this flake (which redeploys domain.xml + setup.sh declaratively — the
# VM disk itself is the only piece that isn't reproducible), or to roll back
# to a known-good disk state.
#
# Memory/uptime state is NOT restored — nas01-backup's virtiofs shares don't
# support that anyway (see docs/nas01.md).
#
# Usage: sudo bash /etc/nas01-backup/vm-restore.sh [archive-name]
#   With no argument, restores from the most recent archive.
#   List archives first with: borg list /pool/borg/nas01
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

REPO=/pool/borg/nas01
DOMAIN=nas01-backup
IMAGES_DIR=/var/lib/libvirt/images
ARCHIVE=${1:-}

export BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase"
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

if [ -z "$ARCHIVE" ]; then
    ARCHIVE=$(borg list --last 1 --format '{archive}' "$REPO" 2>/dev/null || true)
fi
if [ -z "$ARCHIVE" ]; then
    echo "No borg archives found in $REPO. List available: borg list $REPO" >&2
    exit 1
fi

echo "Restoring from archive: $ARCHIVE"

if virsh dominfo "$DOMAIN" >/dev/null 2>&1; then
    echo "Stopping running $DOMAIN..."
    virsh destroy "$DOMAIN" 2>/dev/null || true
fi

mkdir -p "$IMAGES_DIR"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

echo "Extracting VM disk..."
borg extract "$REPO::$ARCHIVE" \
    "var/lib/libvirt/images/$DOMAIN.qcow2" \
    "var/lib/libvirt/images/$DOMAIN-cidata.iso"

cp "$TMPDIR/var/lib/libvirt/images/$DOMAIN.qcow2" "$IMAGES_DIR/$DOMAIN.qcow2"
cp "$TMPDIR/var/lib/libvirt/images/$DOMAIN-cidata.iso" "$IMAGES_DIR/$DOMAIN-cidata.iso"

if ! virsh dominfo "$DOMAIN" >/dev/null 2>&1; then
    echo "Defining $DOMAIN from /etc/nas01-backup/domain.xml..."
    virsh define /etc/nas01-backup/domain.xml
fi

echo "Starting $DOMAIN..."
virsh start "$DOMAIN"
echo "Restore complete."
