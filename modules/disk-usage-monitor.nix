{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Fleet-wide disk usage monitoring for Wazuh — import on any host with
# wazuh-agent (log01, latitude, vm01, nas01, same four as smart-monitor.nix;
# pihole01/02 have no wazuh-agent, airbook-darwin uses a different
# launchd-based service model this module doesn't manage). No options: every
# importing host gets the same poller, same pattern as smart-monitor.nix.
#
# Unlike SMART/ZFS, this needs no dashboard group assignment — the manager
# pushes the `wazuh-disk-usage-status` command localfile fleet-wide via
# wazuh-tailscale's shared/default/agent.conf (alongside the pre-existing
# raw `df -P` entry it complements), since `df` needs no special hardware
# access the way smartctl/zpool do.
#
# wazuh-disk-usage-status (deployed below, synced duplicate of
# wazuh-tailscale's scripts/disk-usage-status.sh) emits one `disk_usage:`
# line per real filesystem plus one `disk_usage_total:` line per host — the
# total reuses the same local-df-plus-zpool-list-separately logic as the
# `dfsum` shell alias (shell-aliases.nix) so the dashboard's "total disk
# usage" figure matches what `dfsum` already reports at the terminal,
# rather than being a second, possibly-divergent definition of "total".
# Decoded by wazuh-tailscale's decoders/disk-usage.xml/rules/
# disk-usage-rules.xml (100824-100829).
#
# Requires nothing new in the wazuh-agent bwrap sandbox — coreutils (df) is
# already in wazuh-agent.nix's targetPkgs, and zpool (only used on nas01)
# is already there for wazuh-zfs-pool-status. wazuh-disk-usage-status just
# needs adding to wazuh-agent.nix's fixPermsScript symlink list, same as
# every other NixOS-deployed script.
{
  systemd.tmpfiles.rules = [
    "d /usr/local/bin 0755 root root -"
    "L+ /usr/local/bin/wazuh-disk-usage-status - - - - ${pkgs.writeShellScript "wazuh-disk-usage-status" (builtins.readFile ./disk-usage-monitor-disk-usage-status.sh)}"
  ];
}
