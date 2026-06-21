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
      procps  # provides ps, used by wazuh-control's pstatus() to verify daemons started
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

    # Apply the same chown/chmod the deb post-install would have run.
    if [ -f /var/ossec/packages_files/agent_installation_scripts/restore-permissions.sh ]; then
      sh /var/ossec/packages_files/agent_installation_scripts/restore-permissions.sh || true
    fi

    # Ensure critical directories are writable by the wazuh user.
    # restore-permissions.sh may not handle all cases correctly on NixOS
    # (e.g. when NSS resolves the wazuh uid differently during activation).
    # queue/sockets is omitted by restore-permissions.sh but wazuh-agentd
    # must create queue/sockets/queue there as the wazuh user.
    chown wazuh:wazuh \
      /var/ossec/etc /var/ossec/etc/shared \
      /var/ossec/queue/rids \
      /var/ossec/queue/sockets \
      /var/ossec/logs \
      /var/ossec/var/run
    chmod 770 \
      /var/ossec/etc /var/ossec/etc/shared \
      /var/ossec/queue/rids \
      /var/ossec/queue/sockets \
      /var/ossec/logs \
      /var/ossec/var/run

    echo "Wazuh agent installed successfully."
  '';

  enrollScript = pkgs.writeShellScript "wazuh-enroll" ''
    set -euo pipefail
    PASSWORD=$(cat ${cfg.enrollmentPasswordFile})
    HOSTNAME=$(${pkgs.hostname}/bin/hostname -s)
    # Run agent-auth directly — it is a Debian ELF binary that resolves fine via
    # nix-ld on the host but fails inside buildFHSEnv bwrap (ld.so cache shadowing).
    /var/ossec/bin/agent-auth \
      -m "${cfg.manager}" \
      -P "$PASSWORD" \
      -A "$HOSTNAME"
    # agent-auth creates client.keys as root:root — fix so wazuh user can read it.
    chown root:wazuh /var/ossec/etc/client.keys
    chmod 640 /var/ossec/etc/client.keys
  '';

  fixPermsScript = pkgs.writeShellScript "wazuh-fix-perms" ''
    set -euo pipefail
    # Ensure ossec.conf and client.keys are root:wazuh readable before each start.
    # agent-auth writes client.keys as root:root on fresh enrollment; this corrects it.
    chown root:wazuh /var/ossec/etc/ossec.conf 2>/dev/null || true
    chmod 660 /var/ossec/etc/ossec.conf 2>/dev/null || true
    if [ -f /var/ossec/etc/client.keys ]; then
      chown root:wazuh /var/ossec/etc/client.keys
      chmod 640 /var/ossec/etc/client.keys
    fi
    # wazuh-agentd (running as wazuh) must create queue/sockets/queue;
    # the install's restore-permissions.sh leaves queue/sockets as root:root 755.
    chown wazuh:wazuh /var/ossec/queue/sockets 2>/dev/null || true
    chmod 770 /var/ossec/queue/sockets 2>/dev/null || true
  '';

  configureScript = pkgs.writeShellScript "wazuh-configure" ''
    set -euo pipefail
    CONF=/var/ossec/etc/ossec.conf
    [ -f "$CONF" ] || exit 0
    # Add remote syslog monitoring stanza if not already present (idempotent)
    if ! ${pkgs.gnugrep}/bin/grep -q '/var/log/remote' "$CONF"; then
      ${pkgs.gnused}/bin/sed -i \
        's|</ossec_config>|  <localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/remote/*/*.log</location>\n  </localfile>\n</ossec_config>|' \
        "$CONF"
    fi
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
    # nix-ld makes Debian-compiled Wazuh ELF binaries (agent-auth, wazuh-*) work
    # directly on NixOS without a chroot/bwrap FHS env.
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib zlib openssl curl libcap ];
    };

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

    # Patch ossec.conf after install: add localfile stanzas not shipped in the deb
    systemd.services.wazuh-agent-configure = {
      description = "Configure Wazuh agent settings";
      wantedBy = [ "wazuh-agent.service" ];
      before = [ "wazuh-agent.service" "wazuh-agent-enroll.service" ];
      after = [ "wazuh-agent-install.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = configureScript;
      };
    };

    # Enroll once — skipped if client.keys already exists and is non-empty.
    # ConditionFileNotEmpty (not ConditionPathExists) so a 0-byte placeholder
    # from the .deb does not suppress enrollment.
    systemd.services.wazuh-agent-enroll = mkIf (cfg.enrollmentPasswordFile != null) {
      description = "Enroll Wazuh agent with manager";
      wantedBy = [ "wazuh-agent.service" ];
      before = [ "wazuh-agent.service" ];
      after = [ "network-online.target" "wazuh-agent-install.service" "wazuh-agent-configure.service" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionFileNotEmpty = "!/var/ossec/etc/client.keys";

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
        ExecStartPre = fixPermsScript;
        ExecStart  = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control start";
        ExecStop   = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control stop";
        ExecReload = "${wazuhFHS}/bin/wazuh-fhs -- /var/ossec/bin/wazuh-control restart";
        Restart    = "on-failure";
        RestartSec = "30s";
        # Only kill the tracked main PID on stop — wazuh-control stop handles
        # the daemon PIDs via their own PID files in /var/ossec/var/run/.
        KillMode   = "process";
      };
    };
  };
}
