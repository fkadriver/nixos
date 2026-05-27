{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Wazuh agent is not in nixpkgs. We install the official .deb via dpkg on
# first boot (ConditionPathExists guards re-runs). The .deb installs to
# /var/ossec; systemd units wrap wazuh-control start/stop.

with lib;

let
  cfg = config.services.wazuh-agent;

  wazuhVersion = "4.14.5";

  wazuhDeb = pkgs.fetchurl {
    url = "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${wazuhVersion}-1_amd64.deb";
    hash = "sha256-eNIpMtZVaXT2e9SIQ0FgloHcYy6nRNvXJV1wSl/V1w0=";
  };

in
{
  options.services.wazuh-agent = {
    enable = mkEnableOption "Wazuh security agent";

    manager = mkOption {
      type = types.str;
      default = "wazuh.warthog-royal.ts.net";
      description = "Wazuh manager hostname or IP";
    };

    enrollmentPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the agent enrollment password (wazuh-authd)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ dpkg ];

    # Install the Wazuh .deb on first boot if /var/ossec doesn't exist yet
    systemd.services.wazuh-agent-install = {
      description = "Install Wazuh agent from official .deb";
      wantedBy = [ "multi-user.target" ];
      before = [ "wazuh-agent-enroll.service" "wazuh-agent.service" ];
      unitConfig.ConditionPathExists = "!/var/ossec/bin/wazuh-agentd";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wazuh-install" ''
          set -euo pipefail
          WAZUH_MANAGER=${cfg.manager} ${pkgs.dpkg}/bin/dpkg -i ${wazuhDeb}
        '';
      };
    };

    # One-shot enrollment — runs agent-auth, skipped if already enrolled
    systemd.services.wazuh-agent-enroll = mkIf (cfg.enrollmentPasswordFile != null) {
      description = "Enroll Wazuh agent with manager";
      wantedBy = [ "wazuh-agent.service" ];
      before = [ "wazuh-agent.service" ];
      after = [ "network-online.target" "wazuh-agent-install.service" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "!/var/ossec/etc/client.keys";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wazuh-enroll" ''
          set -euo pipefail
          PASSWORD=$(cat ${cfg.enrollmentPasswordFile})
          /var/ossec/bin/agent-auth \
            -m ${cfg.manager} \
            -P "$PASSWORD" \
            -A "$(${pkgs.hostname}/bin/hostname -s)"
        '';
      };
    };

    systemd.services.wazuh-agent = {
      description = "Wazuh security agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "wazuh-agent-install.service" ]
        ++ optional (cfg.enrollmentPasswordFile != null) "wazuh-agent-enroll.service";
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "forking";
        ExecStart  = "/var/ossec/bin/wazuh-control start";
        ExecStop   = "/var/ossec/bin/wazuh-control stop";
        ExecReload = "/var/ossec/bin/wazuh-control restart";
        PIDFile    = "/var/ossec/var/run/wazuh-agentd.pid";
        Restart    = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
