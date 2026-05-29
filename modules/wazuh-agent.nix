{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Wazuh agent is not in nixpkgs. We extract the official .deb directly
# (ar + tar, no dpkg) to avoid NixOS PATH/FHS issues with dpkg post-install
# scripts. The FHS env is only needed at runtime so Wazuh's glibc-linked
# binaries resolve /lib/x86_64-linux-gnu etc.

with lib;

let
  cfg = config.services.wazuh-agent;

  wazuhVersion = "4.14.5";

  wazuhDeb = pkgs.fetchurl {
    url = "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${wazuhVersion}-1_amd64.deb";
    hash = "sha256-eNIpMtZVaXT2e9SIQ0FgloHcYy6nRNvXJV1wSl/V1w0=";
  };

  # FHS env for runtime — Wazuh binaries are glibc-linked and expect
  # /lib/x86_64-linux-gnu, /usr/lib, etc.
  wazuhFHS = pkgs.buildFHSEnv {
    name = "wazuh-fhs";
    targetPkgs = p: with p; [
      bash
      coreutils
      glibc
      gcc.cc.lib   # libstdc++, libgcc_s
      zlib
      openssl
      curl
      libcap
    ];
    extraBwrapArgs = [ "--bind" "/var/ossec" "/var/ossec" ];
  };

  installScript = pkgs.writeShellScript "wazuh-install" ''
    set -euo pipefail

    # tar needs compression helpers in PATH (gzip/xz/zstd depending on .deb version)
    export PATH="${pkgs.gzip}/bin:${pkgs.xz}/bin:${pkgs.zstd}/bin:${pkgs.coreutils}/bin:$PATH"

    # Extract the .deb manually — avoids dpkg post-install script PATH issues on NixOS.
    # A .deb is an ar archive containing control.tar.* and data.tar.*.
    WORK=$(mktemp -d)
    trap "rm -rf $WORK" EXIT

    ${pkgs.binutils}/bin/ar x --output="$WORK" ${wazuhDeb}

    # data.tar may be .xz, .gz, or .zst depending on deb version
    DATA=$(ls "$WORK"/data.tar.* 2>/dev/null | head -1)
    if [ -z "$DATA" ]; then
      echo "ERROR: no data.tar.* found in .deb" >&2
      exit 1
    fi

    # Extract only ./var/ossec into a staging dir, then move into place.
    # Never extract to / — the deb contains /usr, /etc, and other paths that
    # would overwrite NixOS system files including the bootloader.
    STAGE=$(mktemp -d)
    trap "rm -rf $WORK $STAGE" EXIT

    ${pkgs.gnutar}/bin/tar -xf "$DATA" -C "$STAGE" \
      --no-same-owner \
      --no-overwrite-dir \
      --wildcards './var/ossec'

    if [ ! -d "$STAGE/var/ossec" ]; then
      echo "ERROR: /var/ossec not found in .deb data archive" >&2
      exit 1
    fi

    # Atomic-ish move: copy into place so a partial failure leaves ossec.conf
    # absent (ConditionPathExists guard re-triggers) rather than half-written.
    cp -a "$STAGE/var/ossec/." /var/ossec/

    # Patch manager address into the shipped ossec.conf template
    if [ ! -f /var/ossec/etc/ossec.conf ]; then
      echo "ERROR: ossec.conf not found after extraction" >&2
      exit 1
    fi
    ${pkgs.gnused}/bin/sed -i \
      's|<address>.*</address>|<address>${cfg.manager}</address>|' \
      /var/ossec/etc/ossec.conf

    echo "Wazuh agent installed successfully."
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
    # wazuh user/group expected by the agent binaries
    users.users.wazuh = {
      isSystemUser = true;
      group = "wazuh";
      home = "/var/ossec";
      description = "Wazuh agent service user";
    };
    users.groups.wazuh = {};

    # Install the .deb contents once — guard on ossec.conf presence
    systemd.services.wazuh-agent-install = {
      description = "Install Wazuh agent from official .deb";
      wantedBy = [ "multi-user.target" ];
      before = [ "wazuh-agent-enroll.service" "wazuh-agent.service" ];
      unitConfig.ConditionPathExists = "!/var/ossec/etc/ossec.conf";

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
