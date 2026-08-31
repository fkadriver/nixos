{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Fleet-wide SMART drive health monitoring for Wazuh — import on any host
# with wazuh-agent and a real disk (log01, latitude, vm01, nas01 as of
# 2026-08-31; pihole01/02 have no wazuh-agent, airbook-darwin has no
# smartmontools/different service model). No options: every importing host
# gets the same two mechanisms, same pattern as fwupd.nix. Always import
# alongside wazuh-agent — the extraLocalFiles entry below assumes it exists.
#
# 1. Real-time alert: smartd -M exec fires this script on any SMART
#    failure/attribute change, appended to /var/log/smartd-alerts.log and
#    forwarded via extraLocalFiles (syslog format) — decoded by
#    wazuh-tailscale's decoders/smart-status.xml (nas01-smartd-alert),
#    rule 100818. Originally nas01-only; generalized here (message text no
#    longer hardcodes a hostname — rsyslog/Wazuh already stamp agent.name).
#
# 2. Periodic poll: wazuh-smart-status (deployed below, synced duplicate of
#    wazuh-tailscale's scripts/smart-status.sh) runs smartctl against every
#    real disk. Invoked directly by the Wazuh manager as a `command`
#    localfile (shared/smart-monitor/agent.conf, frequency 3600) once the
#    agent is assigned to the "smart-monitor" group via the dashboard — not
#    a NixOS-managed timer, same as wazuh-zfs-pool-status. This is what
#    gives the dashboard a baseline OK/warning table instead of only ever
#    showing failures (the same "rollup gap" nas01-borg-status hit).
#
# Requires smartctl (smartmontools, already in common.nix's systemPackages)
# and jq/lsblk to also be available inside the wazuh-agent's bwrap FHS env
# (wazuh-agent.nix's targetPkgs) and wazuh-smart-status added to its
# scripts-symlink list — bwrap hides /usr/local/bin from wazuh-logcollector,
# see feedback_wazuh_bwrap_scripts in project memory.

let
  smartdAlertScript = pkgs.writeShellScript "smartd-alert" ''
    LOG=/var/log/smartd-alerts.log
    echo "$(date '+%b %d %H:%M:%S') $(hostname) smartd: ALERT device=''${SMARTD_DEVICE:-unknown} type=''${SMARTD_FAILTYPE:-unknown} msg=''${SMARTD_MESSAGE:-}" >> "$LOG"
  '';
in
{
  services.smartd = {
    enable = true;
    defaults.monitored = "-a -M exec ${smartdAlertScript}";
  };

  systemd.tmpfiles.rules = [
    "d /usr/local/bin 0755 root root -"
    "L+ /usr/local/bin/wazuh-smart-status - - - - ${pkgs.writeShellScript "wazuh-smart-status" (builtins.readFile ./smart-monitor-smart-status.sh)}"
  ];

  services.wazuh-agent.extraLocalFiles = [
    { location = "/var/log/smartd-alerts.log"; logFormat = "syslog"; }
  ];
}
