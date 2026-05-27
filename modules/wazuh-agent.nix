{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Wazuh agent is not in nixpkgs. The official .deb is installed via dpkg
# inside a buildFHSEnv wrapper so Wazuh's glibc-linked binaries find their
# expected paths (/lib/x86_64-linux-gnu, /usr/lib, etc.) on NixOS.
# State lives in /var/ossec (Wazuh's standard prefix).

with lib;

let
  cfg = config.services.wazuh-agent;

  wazuhVersion = "4.14.5";

  wazuhDeb = pkgs.fetchurl {
    url = "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${wazuhVersion}-1_amd64.deb";
    hash = "sha256-eNIpMtZVaXT2e9SIQ0FgloHcYy6nRNvXJV1wSl/V1w0=";
  };

  # FHS environment that provides the glibc paths Wazuh's binaries expect.
  # dpkg is run inside it so post-install scripts also resolve correctly.
  wazuhFHS = pkgs.buildFHSEnv {
    name = "wazuh-fhs";
    targetPkgs = p: with p; [
      glibc
      gcc.cc.lib   # libstdc++, libgcc_s
      zlib
      openssl
      curl
      libcap
    ];
    # Make /var/ossec writable through to the real host path
    extraBwrapArgs = [ "--bind" "/var/ossec" "/var/ossec" ];
  };

  installScript = pkgs.writeShellScript "wazuh-install" ''
    set -euo pipefail
    mkdir -p /var/ossec
    # Set manager address before dpkg so the post-install script picks it up
    export WAZUH_MANAGER="${cfg.manager}"
    ${wazuhFHS}/bin/wazuh-fhs -- ${pkgs.dpkg}/bin/dpkg -i ${wazuhDeb}
  '';

  enrollScript = pkgs.writeShellScript "wazuh-enroll" ''
    set -euo pipefail
    PASSWORD=$(cat ${cfg.enrollmentPasswordFile})
    HOSTNAME=$(${pkgs.hostname}/bin/hostname -s)
    ${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/agent-auth \
      -m "${cfg.manager}" \
      -P "$PASSWORD" \
      -A "$HOSTNAME"
  '';

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
      description = "Path to file containing the agent enrollment password";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.dpkg ];

    # Install the .deb once — skipped if already done
    systemd.services.wazuh-agent-install = {
      description = "Install Wazuh agent from official .deb";
      wantedBy = [ "multi-user.target" ];
      before = [ "wazuh-agent-enroll.service" "wazuh-agent.service" ];
      unitConfig.ConditionPathExists = "!/var/ossec/bin/wazuh-agentd";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = installScript;
      };
    };

    # Enroll once — skipped if client.keys already exists
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
        ExecStart = enrollScript;
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
        ExecStart  = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control start";
        ExecStop   = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control stop";
        ExecReload = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control restart";
        PIDFile    = "/var/ossec/var/run/wazuh-agentd.pid";
        Restart    = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
