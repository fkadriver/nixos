{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.idrive-e360;

  # Build iDrive e360 from local .deb file if provided
  idrivePackage = if cfg.debFile != null then
    pkgs.callPackage ../pkgs/idrive-e360 { src = cfg.debFile; }
  else
    pkgs.callPackage ../pkgs/idrive-e360 { };
in
{
  options.services.idrive-e360 = {
    enable = mkEnableOption "iDrive e360 backup service";

    debFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "/path/to/idrive360.deb";
      description = ''
        Path to a locally downloaded iDrive e360 .deb file.
        Download from: https://www.idrive.com/endpoint-backup/ -> Add Devices -> Linux tab
        If not provided, will attempt to fetch from a default URL (which may not work).
      '';
    };

    package = mkOption {
      type = types.package;
      default = idrivePackage;
      defaultText = literalExpression "pkgs.idrive-e360";
      description = "The iDrive e360 package to use";
    };

    user = mkOption {
      type = types.str;
      default = "scott";
      description = "User account for iDrive e360 backups";
    };

    configDir = mkOption {
      type = types.str;
      default = "/home/${cfg.user}/.idrive360";
      description = "Directory for iDrive e360 configuration files";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/home/${cfg.user}";
      description = "Root directory to backup";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically start the iDrive e360 service";
    };

    scheduledBackup = {
      enable = mkEnableOption "scheduled automatic backups";

      schedule = mkOption {
        type = types.str;
        default = "daily";
        example = "hourly";
        description = ''
          Schedule for automatic backups. Can be:
          - A systemd.time calendar event (e.g., "daily", "weekly", "00:00", "Mon 09:00")
          - See systemd.time(7) for full syntax
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Add iDrive e360 package to system packages
    environment.systemPackages = [ cfg.package ];

    # Create iDrive e360 systemd service
    systemd.services.idrive-e360 = {
      description = "iDrive e360 Backup Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = mkIf cfg.autoStart [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${cfg.package}/bin/idrive360";
        Restart = "on-failure";
        RestartSec = "30s";

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.configDir cfg.dataDir ];
      };
    };

    # Scheduled backup timer (if enabled)
    systemd.timers.idrive-e360-backup = mkIf cfg.scheduledBackup.enable {
      description = "iDrive e360 Scheduled Backup Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.scheduledBackup.schedule;
        Persistent = true;
        Unit = "idrive-e360-backup.service";
      };
    };

    systemd.services.idrive-e360-backup = mkIf cfg.scheduledBackup.enable {
      description = "iDrive e360 Scheduled Backup";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart = "${cfg.package}/bin/idrive360 --backup";

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.configDir cfg.dataDir ];
      };
    };

    # Ensure config directory exists
    system.activationScripts.idrive-e360-setup = ''
      if [ ! -d "${cfg.configDir}" ]; then
        mkdir -p "${cfg.configDir}"
        chown ${cfg.user}:users "${cfg.configDir}"
        chmod 700 "${cfg.configDir}"
      fi
    '';
  };
}
