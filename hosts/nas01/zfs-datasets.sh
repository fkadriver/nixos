#!/bin/bash
# Ensures nas01's ZFS pool is imported and its managed datasets exist with
# their declared properties (quota, compression). Safe to re-run any time —
# idempotent. Run as root on nas01: sudo bash /etc/nas01-zfs/zfs-datasets.sh
#
# This is the "declarative" layer for ZFS *datasets* that NixOS itself
# doesn't provide: `boot.zfs.extraPools = [ "pool" ];` in default.nix only
# imports an already-existing pool at boot, it says nothing about which
# datasets should exist inside it or what properties they should carry.
# Add new datasets to the DATASETS table below instead of running one-off
# `zfs create` commands by hand, so quota/compression changes are a diff +
# a re-run of this script, not tribal knowledge.
#
# What this does NOT do: create a pool from scratch. If `zpool import`
# fails, that means the pool's member disks themselves are gone — not just
# an OS reinstall — and recreating a RAIDZ1 pool blindly would be
# destructive if any of those disks are actually salvageable. That step
# stays manual and deliberate; see docs/nas01.md's "Disaster Recovery"
# section for the by-hand `zpool create` procedure once you've confirmed
# which disks are really gone.
set -euo pipefail

POOL="pool"

if zpool list "$POOL" >/dev/null 2>&1; then
  echo "Pool '$POOL' already imported ($(zpool list -H -o health "$POOL"))."
else
  echo "Pool '$POOL' not imported — attempting import..."
  if zpool import -f "$POOL"; then
    echo "Imported '$POOL' ($(zpool list -H -o health "$POOL"))."
  else
    echo
    echo "FAILED to import '$POOL'."
    echo "This means the pool's member disks aren't present/visible to this"
    echo "OS install, not just a routine OS-disk reinstall (those recover"
    echo "with a plain 'zpool import -f pool', which this script already"
    echo "tried). Do not run 'zpool create' speculatively — see docs/nas01.md"
    echo "'Disaster Recovery' for the manual rebuild procedure: confirm"
    echo "which disks are really gone, identify survivors by serial/by-id,"
    echo "and recreate deliberately from there."
    exit 1
  fi
fi

# dataset path -> comma-separated zfs properties (same syntax `zfs set`/
# `zfs create -o` take)
declare -A DATASETS=(
  ["$POOL/rsyslog"]="compression=lz4,quota=1.5T"
)

for ds in "${!DATASETS[@]}"; do
  IFS=',' read -ra opts <<< "${DATASETS[$ds]}"
  if zfs list "$ds" >/dev/null 2>&1; then
    echo "Dataset '$ds' exists — ensuring properties: ${DATASETS[$ds]}"
    for opt in "${opts[@]}"; do
      zfs set "$opt" "$ds"
    done
  else
    echo "Creating dataset '$ds' with properties: ${DATASETS[$ds]}"
    create_args=()
    for opt in "${opts[@]}"; do
      create_args+=("-o" "$opt")
    done
    zfs create "${create_args[@]}" "$ds"
  fi
done

echo
echo "Current state:"
zfs list -o name,used,avail,quota,compression -r "$POOL"
