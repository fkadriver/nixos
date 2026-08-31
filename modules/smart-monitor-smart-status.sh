#!/usr/bin/env bash
# Fleet-wide SMART health poller (log01, latitude, vm01, nas01 — every
# wazuh-agent host with a real disk; pihole01/02 have no agent, airbook-darwin
# has no smartmontools).
#
# Emits one 'smart_device: ...' line per physical drive from `smartctl
# --json` (smartmontools 7.x). Unifies ATA and NVMe into one schema so a
# single decoder/rule set covers both bus types:
#   - health:        smart_status.passed (present on both bus types)
#   - reallocated:   ATA attribute 5 (Reallocated_Sector_Ct) raw value, else 0
#   - pending:       ATA attribute 197 (Current_Pending_Sector) raw value, else 0
#   - media_errors:  NVMe nvme_smart_health_information_log.media_errors, else 0
#   - temp_c:        temperature.current (present on both bus types), else 0
# "else 0" is a deliberate simplification, not a real zero reading — an
# attribute that doesn't apply to a drive's bus type reports as absent rather
# than a distinct "N/A", same tradeoff already made for zfs-pool-status.sh's
# error counts (see decoders/smart-status.xml header for why OS_Regex wants
# plain digits here anyway).
#
# Drive discovery: every `disk`-type block device from `lsblk`, skipping any
# device smartctl can't get a smart_status for (SD/eMMC cards, USB card
# readers, etc. — no reliable SMART support).
#
# Per-drive smartctl calls run IN PARALLEL (backgrounded, joined with `wait`)
# rather than sequentially. Confirmed the hard way on nas01 (5 SATA drives):
# sequential took 5.02s wall time and Wazuh's `command`-type localfile
# execution silently discards output that doesn't complete within its
# internal timeout (~5s) — the script ran fine standalone and even inside
# the agent's own bwrap sandbox manually, registered cleanly in
# logcollector's config with zero errors logged, yet never once produced an
# alert, while an identically-configured 60s-frequency ZFS command kept
# firing like clockwork the whole time. Parallelizing keeps total wall time
# close to the single slowest drive instead of the sum of all of them.
# Each background job computes and prints its own single line — safe to
# interleave with `wait` since each line is well under PIPE_BUF and printed
# in one write.
#
# Deploy to /var/ossec/scripts/wazuh-smart-status as a `command` localfile
# (see shared/smart-monitor/agent.conf) — same convention as
# wazuh-zfs-pool-status.
#
# Canonical/documented copy lives in wazuh-tailscale's
# config/wazuh_cluster/scripts/smart-status.sh — this is a synced duplicate
# so NixOS's flake (pure eval) can deploy it without reading outside its own
# source tree, same as github-ci-status.sh/wazuh-tailscale-health.sh.
#
# Requires: smartctl (smartmontools), jq. Must run as root (or with
# CAP_SYS_RAWIO) to read SMART data — the wazuh-agent already runs as root.

set -uo pipefail

poll_device() {
  local path="$1"
  local json passed health reallocated pending media_errors temp_c

  json=$(smartctl -H -A --json=c "$path" 2>/dev/null)
  passed=$(echo "$json" | jq -r '.smart_status.passed // empty' 2>/dev/null)
  if [ -z "$passed" ]; then
    return
  fi

  health="FAILED"
  [ "$passed" = "true" ] && health="PASSED"

  reallocated=$(echo "$json" | jq -r '[.ata_smart_attributes.table[]? | select(.id == 5) | .raw.value] | first // 0')
  pending=$(echo "$json" | jq -r '[.ata_smart_attributes.table[]? | select(.id == 197) | .raw.value] | first // 0')
  media_errors=$(echo "$json" | jq -r '.nvme_smart_health_information_log.media_errors // 0')
  temp_c=$(echo "$json" | jq -r '.temperature.current // 0')

  echo "smart_device: device=${path} health=${health} reallocated=${reallocated} pending=${pending} media_errors=${media_errors} temp_c=${temp_c}"
}

for dev in $(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" {print $1}'); do
  poll_device "/dev/${dev}" &
done
wait
