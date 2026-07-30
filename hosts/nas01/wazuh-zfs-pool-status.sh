#!/usr/bin/env bash
# ZFS pool health poller (nas01's "pool" raidz1).
#
# Emits one 'zfs_pool: ...' line per pool (overall state, current/last scrub)
# and one 'zfs_device: ...' line per leaf device (per-disk read/write/
# checksum error counts) from `zpool status --json`. Device-level detail
# matters because a raidz pool can still report overall state=ONLINE while
# one member disk is quietly accumulating errors — that's the early warning
# a pool-level check alone would miss entirely.
#
# Deploy to /var/ossec/scripts/wazuh-zfs-pool-status (see borg-status.sh's
# deployment note in README).
#
# Requires: zpool (root — the wazuh-agent already runs as root here), jq.
# `zpool status --json` verified available on ZFS 2.4.3.
#
# Canonical/documented copy lives in wazuh-tailscale's
# config/wazuh_cluster/scripts/zfs-pool-status.sh — this is a synced
# duplicate so NixOS's flake (pure eval) can deploy it without reading
# outside its own source tree, same as github-ci-status.sh/wazuh-tailscale-health.sh.

set -uo pipefail

STATUS=$(zpool status --json 2>&1)
if ! echo "$STATUS" | jq -e . >/dev/null 2>&1; then
  echo "zfs_pool: pool=- state=ERROR error=zpool_status_failed"
  exit 0
fi

echo "$STATUS" | jq -r '
  .pools | to_entries[] | .key as $pool | .value |
  [$pool, .state, (.scan_stats.function // "NONE"), (.scan_stats.state // "NONE"), (.scan_stats.errors // "0")] | @tsv
' | while IFS=$'\t' read -r pool state scan_function scan_state scan_errors; do
  echo "zfs_pool: pool=${pool} state=${state} scan_function=${scan_function} scan_state=${scan_state} scan_errors=${scan_errors}"
done

echo "$STATUS" | jq -r '
  .pools | to_entries[] | .key as $pool | .value.vdevs | .. | objects | select(.vdev_type? == "disk") |
  [$pool, .name, .state, .read_errors, .write_errors, .checksum_errors] | @tsv
' | while IFS=$'\t' read -r pool device state read_errors write_errors checksum_errors; do
  echo "zfs_device: pool=${pool} device=${device} state=${state} read_errors=${read_errors} write_errors=${write_errors} checksum_errors=${checksum_errors}"
done
