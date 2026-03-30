#!/usr/bin/env bash
# Writes a NixOS installer ISO to a USB drive and appends a 500MB FAT32
# read-write partition (label: NIXOS_DATA) in the remaining space.
#
# After installing a new host, plug this USB into the new system and run:
#   sudo mount LABEL=NIXOS_DATA /mnt/usb-data
#   sudo age-keygen -y /var/lib/sops-nix/key.txt | sudo tee /mnt/usb-data/$(hostname)-age.pub
#   sudo umount /mnt/usb-data
# Then bring the USB back and add the key to .sops.yaml.
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

# Unmount any partitions on the device
echo ""
echo "Unmounting partitions on $DEVICE..."
umount "${DEVICE}"?* 2>/dev/null || umount "${DEVICE}"p?* 2>/dev/null || true

echo "Writing ISO to $DEVICE..."
dd if="$ISO" of="$DEVICE" bs=4M status=progress
echo "Flushing write cache to device (may take a minute)..."
sync

# The ISO embeds the GPT backup header and sets LastUsableLBA to the ISO size,
# not the physical end of the USB. gdisk expert mode "x → e" relocates the
# backup GPT and updates LastUsableLBA to the actual disk end, which is
# required before parted can create a partition in the free space.
echo "Fixing GPT to reflect full device size..."
printf "x\ne\nw\nY\n" | gdisk "$DEVICE"

ISO_SIZE_MiB=$(( ($(stat -c %s "$ISO") + 1048575) / 1048576 ))
PART_START_MiB=$(( ISO_SIZE_MiB + 1 ))

echo "Creating 500MB NIXOS_DATA partition at ${PART_START_MiB}MiB..."
parted -sf "$DEVICE" mkpart primary fat32 "${PART_START_MiB}MiB" "$((PART_START_MiB + 500))MiB"

# Tell kernel about the new partition
partprobe "$DEVICE" 2>/dev/null || true
sleep 2

# Find the new partition: last name reported by lsblk for this device
PART="/dev/$(lsblk -ln -o NAME "$DEVICE" | grep -v "^$(basename "$DEVICE")$" | tail -1)"

echo "Formatting $PART as FAT32 (label: NIXOS_DATA)..."
mkfs.fat -F32 -n NIXOS_DATA "$PART"

echo ""
echo "=== Done! ==="
echo "Boot device:    $DEVICE"
echo "Data partition: $PART  (FAT32, label: NIXOS_DATA)"
echo ""
echo "The installer will auto-mount NIXOS_DATA at /mnt/usb-data on boot."
echo ""
echo "After installing and first-booting a new NixOS host:"
echo "  1. Reboot into the new system, let it fully boot (age key is generated on first boot)"
echo "  2. Plug this USB drive into the new system"
echo "  3. sudo mount LABEL=NIXOS_DATA /mnt/usb-data"
echo "  4. sudo age-keygen -y /var/lib/sops-nix/key.txt | sudo tee /mnt/usb-data/\$(hostname)-age.pub"
echo "  5. sudo umount /mnt/usb-data"
echo "  6. Bring USB back to your management machine and add the key:"
echo "       mount $PART /mnt/nixos-data"
echo "       cat /mnt/nixos-data/<hostname>-age.pub"
echo "     Then add to .sops.yaml and run: sops updatekeys secrets/secrets.yaml"
