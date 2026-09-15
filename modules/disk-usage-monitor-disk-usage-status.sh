#!/usr/bin/env bash
# Fleet-wide disk usage poller — every wazuh-agent host (all of shared/default,
# no group assignment needed, unlike SMART/ZFS). Wazuh's built-in `df -P`
# localfile (see shared/default/agent.conf, rule 530/531) already ships raw
# df output and alerts once a filesystem hits 100% full, but never decodes
# it into fields — so there's no baseline usage row on the dashboard, no
# numeric percent to chart, and no warning before a filesystem is already
# full. This emits two kinds of structured line instead:
#
#   disk_usage:       one per real filesystem (per-mount detail)
#   disk_usage_total: one per host (single "how full is this machine" figure)
#
# The total line reuses the exact same sum-then-add-ZFS-separately logic as
# the `dfsum` shell alias (modules/shell-aliases.nix) rather than inventing
# a different definition of "total" — `df` doesn't sum across filesystems,
# and naively summing every df row would double-count a ZFS pool's shared
# free space across each of its mounted datasets. Local device-backed
# filesystems ($1 ~ /^\/dev\//, same filter dfsum uses) are summed via df,
# then `zpool list` alloc/size/free is added on top for hosts with ZFS —
# pool datasets never match /^\/dev\//, so there's no overlap between the
# two sums.
#
# status (ok/warning/critical) is computed HERE, not in Wazuh rules —
# OS_Regex <field> matching can't reliably do numeric thresholds or negation
# (bracket classes like [1-9] silently never match; see
# nas01-health-rules.xml/opnsense-filterlog.xml), so this follows
# tailscale-health-status.sh's approach of pre-computing a status field and
# letting rules do plain literal matches on it.
#
# Pseudo/virtual filesystems (tmpfs, overlay, proc, sysfs, cgroup, etc.) are
# excluded from the per-mount lines via `df`'s Type column — not meaningful
# "disk usage", would just be noise duplicated across every host.
#
# `-B1` gets exact byte counts directly from df instead of POSIX -P's
# ambiguous default block size (512 vs 1024 depending on df implementation/
# environment) — no unit conversion needed downstream.
#
# Deploy to /var/ossec/scripts/wazuh-disk-usage-status as a `command`
# localfile (see shared/default/agent.conf) — same convention as
# wazuh-zfs-pool-status/wazuh-smart-status.
#
# Canonical/documented copy lives in wazuh-tailscale's
# config/wazuh_cluster/scripts/disk-usage-status.sh — this is a synced
# duplicate so NixOS's flake (pure eval) can deploy it without reading
# outside its own source tree, same as smart-monitor-smart-status.sh.
#
# Requires GNU coreutils df (-T, -B1). On a host without GNU df (e.g.
# airbook-darwin's BSD df), these flags are simply rejected, df exits
# nonzero, and the read loops below get no input — the script just emits
# nothing rather than garbage. Same graceful-skip tradeoff as
# smart-status.sh on hosts without smartmontools.

set -uo pipefail

WARN_PCT=85
CRIT_PCT=95

status_for_pcent() {
  local pcent="$1"
  if [ "$pcent" -ge "$CRIT_PCT" ]; then
    echo critical
  elif [ "$pcent" -ge "$WARN_PCT" ]; then
    echo warning
  else
    echo ok
  fi
}

EXCLUDE_TYPES='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup|cgroup2|nsfs|devpts|mqueue|hugetlbfs|efivarfs|debugfs|tracefs|configfs|binfmt_misc|autofs|rpc_pipefs|ramfs)$'

df -PT -B1 2>/dev/null | tail -n +2 | while read -r device fstype size used avail pcent mount; do
  [[ "$fstype" =~ $EXCLUDE_TYPES ]] && continue

  pcent_num="${pcent%\%}"
  status=$(status_for_pcent "$pcent_num")

  mount_safe=$(echo "$mount" | tr ' ' '_')
  echo "disk_usage: mount=${mount_safe} device=${device} fstype=${fstype} size_bytes=${size} used_bytes=${used} avail_bytes=${avail} pcent_used=${pcent_num} status=${status}"
done

read -r local_used_kb local_size_kb local_avail_kb <<<"$(df -kP -l 2>/dev/null | awk 'NR>1 && $1 ~ /^\/dev\//{u+=$3;s+=$2;a+=$4} END{print u+0, s+0, a+0}')"

zfs_used_kb=0
zfs_size_kb=0
zfs_avail_kb=0
if command -v zpool >/dev/null 2>&1 && [ -n "$(zpool list -H 2>/dev/null)" ]; then
  read -r zfs_used_kb zfs_size_kb zfs_avail_kb <<<"$(zpool list -Hp -o alloc,size,free 2>/dev/null | awk '{u+=$1;s+=$2;a+=$3} END{printf "%d %d %d\n", u/1024, s/1024, a/1024}')"
fi

total_used_kb=$(( ${local_used_kb:-0} + ${zfs_used_kb:-0} ))
total_size_kb=$(( ${local_size_kb:-0} + ${zfs_size_kb:-0} ))
total_avail_kb=$(( ${local_avail_kb:-0} + ${zfs_avail_kb:-0} ))

if [ "$total_size_kb" -gt 0 ]; then
  total_pcent=$(( total_used_kb * 100 / total_size_kb ))
  total_status=$(status_for_pcent "$total_pcent")
  echo "disk_usage_total: size_bytes=$((total_size_kb * 1024)) used_bytes=$((total_used_kb * 1024)) avail_bytes=$((total_avail_kb * 1024)) pcent_used=${total_pcent} status=${total_status}"
fi
