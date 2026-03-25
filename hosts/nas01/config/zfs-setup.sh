#!/usr/bin/env bash
# ZFS RAIDZ1 pool setup for nas01
# Run AFTER connecting the 3x 4TB drives and identifying their disk IDs.
#
# IMPORTANT: Always use /dev/disk/by-id/ paths, never /dev/sdX (can change on reboot).
#
# Prerequisites (via apt on Ubuntu):
#   sudo apt install zfsutils-linux
#
# Step 1: Identify drives
#   ls -la /dev/disk/by-id/ | grep -v part
#   lsblk -o NAME,SIZE,MODEL,SERIAL
#
# Step 2: Fill in the DISK variables below, then run this script.


# /dev/sdb: UUID="22fad4b1-2592-4407-b93d-03efd7a72291" UUID_SUB="9aba248d-4eb8-4892-86ff-c6062291c498" BLOCK_SIZE="4096" TYPE="btrfs"
# /dev/sdc: UUID="22fad4b1-2592-4407-b93d-03efd7a72291" UUID_SUB="9bb326ef-f66c-4341-8eaa-f8a580d36ba9" BLOCK_SIZE="4096" TYPE="btrfs"
# /dev/sde: UUID="22fad4b1-2592-4407-b93d-03efd7a72291" UUID_SUB="6f3e4a49-92c8-474d-8fb4-c8cf472a0c52" BLOCK_SIZE="4096" TYPE="btrfs"

set -euo pipefail

# TODO: Replace these with actual disk IDs from: ls /dev/disk/by-id/
DISK1="/dev/disk/by-id/ata-HGST_HDS724040ALE640_PK1301PAJ2480X"  # sdb
DISK2="/dev/disk/by-id/ata-HGST_HDS724040ALE640_PK2331PAJEL1NT"  # sdc
DISK3="/dev/disk/by-id/ata-HGST_HDS724040ALE640_PK1301PAJ44X6S"  # sdd

POOL_NAME="pool"
POOL_MOUNT="/pool"

# Validate placeholders are replaced
for disk in "$DISK1" "$DISK2" "$DISK3"; do
    if [[ "$disk" == *"REPLACE_WITH"* ]]; then
        echo "ERROR: Set DISK1, DISK2, DISK3 variables before running."
        exit 1
    fi
    if [[ ! -e "$disk" ]]; then
        echo "ERROR: Disk not found: $disk"
        exit 1
    fi
done

echo "=== ZFS RAIDZ1 Pool Setup ==="
echo "Pool:  ${POOL_NAME}"
echo "Mount: ${POOL_MOUNT}"
echo "Disks: ${DISK1}"
echo "       ${DISK2}"
echo "       ${DISK3}"
echo ""
read -rp "Confirm: this will DESTROY all data on these disks. Continue? [yes/N] " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

# Create RAIDZ1 pool
# ashift=12: 4K sector alignment (use 13 for 8K sectors, check with smartctl)
# compression=lz4: fast transparent compression
# atime=off: skip access time updates (NAS performance)
zpool create \
    -o ashift=12 \
    -O compression=lz4 \
    -O atime=off \
    -O xattr=sa \
    -O dnodesize=auto \
    -O normalization=formD \
    -m "${POOL_MOUNT}" \
    "${POOL_NAME}" \
    raidz \
    "${DISK1}" "${DISK2}" "${DISK3}"

echo "Pool created. Verifying..."
zpool status "${POOL_NAME}"

# Create datasets
echo ""
echo "Creating datasets..."

# Main data dataset
zfs create "${POOL_NAME}/data"

# Note: Borg repos are on the WD 18TB drive at /mnt/wd18t_3/borg, not on this ZFS pool.

# Optional: separate dataset per use case for independent snapshots
# zfs create "${POOL_NAME}/media"
# zfs create "${POOL_NAME}/photos"

echo ""
echo "Datasets created:"
zfs list "${POOL_NAME}"
echo ""
echo "=== Next Steps ==="
echo "1. Set permissions:  chown -R scott:scott /pool/data"
echo "2. Create borg dirs: mkdir -p /mnt/wd18t_3/borg/{latitude,vm01,airbook-darwin}"
echo "3. Run:              ./borg-server-setup.sh"
echo "4. Enable scrub:     systemctl enable zfs-scrub-weekly@${POOL_NAME}.timer"
echo ""
echo "=== Btrfs Migration ==="
echo "When migrating data from btrfs drives:"
echo "  1. Connect btrfs drive"
echo "  2. Mount: mount -o ro /dev/sdX /mnt/source"
echo "  3. Copy:  rsync -avHX /mnt/source/ /pool/data/"
echo "  4. Verify, then wipe btrfs drive"
