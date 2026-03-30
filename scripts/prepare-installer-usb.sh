#!/usr/bin/env bash
# Writes a NixOS installer ISO to a USB drive.
#
# NOTE: Adding a persistent read-write data partition to the NixOS hybrid ISO
# is not feasible with standard tools. The ISO format embeds ISO 9660 data
# that overlaps the GPT partition entries, causing gdisk/sgdisk/parted to
# abort any partition table modifications. A raw disk image format (not ISO)
# would be required for a proper multi-partition installer USB.
#
# To transfer an AGE key after installing a new host, use SSH instead:
#   ssh scott@<hostname> 'sudo age-keygen -y /var/lib/sops-nix/key.txt'
#   # paste output into .sops.yaml, then:
#   sops updatekeys secrets/secrets.yaml
#
# Usage: sudo ./scripts/prepare-installer-usb.sh <iso-path> <usb-device>
# Example: sudo ./scripts/prepare-installer-usb.sh result/iso/nixos-*.iso /dev/sdb

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <iso-path> <usb-device>"
    echo "Example: $0 result/iso/nixos-*.iso /dev/sdb"
    exit 1
fi

ISO="$1"
DEVICE="$2"

[[ -f "$ISO" ]]  || { echo "Error: ISO '$ISO' not found"; exit 1; }
[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Error: run with sudo"; exit 1; }

echo "=== NixOS Installer USB Preparation ==="
echo "ISO:    $ISO ($(du -sh "$ISO" | cut -f1))"
echo "Device: $DEVICE"
echo ""
lsblk "$DEVICE"
echo ""
echo "WARNING: ALL DATA on $DEVICE will be erased."
read -rp "Continue? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Cancelled."; exit 0; }

echo ""
echo "Unmounting partitions on $DEVICE..."
umount "${DEVICE}"?* 2>/dev/null || umount "${DEVICE}"p?* 2>/dev/null || true

echo "Writing ISO to $DEVICE..."
dd if="$ISO" of="$DEVICE" bs=4M status=progress
echo "Flushing write cache to device (may take a minute)..."
sync

echo ""
echo "=== Done! ==="
echo "USB drive ready: $DEVICE"
echo ""
echo "After installing and first-booting a new NixOS host, get the AGE key via SSH:"
echo "  ssh scott@<hostname> 'sudo age-keygen -y /var/lib/sops-nix/key.txt'"
echo "  # Add the output to .sops.yaml, then:"
echo "  sops updatekeys secrets/secrets.yaml"
