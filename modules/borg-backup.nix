{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.borg-backup;
in
{
  options.services.borg-backup = {
    enable = mkEnableOption "Borg backup service";

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to run backups as";
    };

    repository = mkOption {
      type = types.str;
      example = "ssh://user@nas01/path/to/repo";
      description = "Borg repository location";
    };

    paths = mkOption {
      type = types.listOf types.str;
      default = [ "/home" ];
      description = "Paths to back up";
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        "*/cache"
        "*/Cache"
        "*/.cache"
        "*/.Cache"
        "*/node_modules"
        "*/.npm"
        "*/.cargo"
        "*/.rustup"
        "*/.local/share/Trash"
        "*/.Trash"
        "*.pyc"
        "*/__pycache__"
        "*/.nix-defexpr"
        "*/.nix-profile"
      ];
      description = "Patterns to exclude from backup";
    };

    encryption = {
      mode = mkOption {
        type = types.enum [ "none" "repokey" "repokey-blake2" "keyfile" "keyfile-blake2" ];
        default = "repokey-blake2";
        description = "Encryption mode for the repository";
      };

      passphraseFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the repository passphrase";
      };
    };

    prune = {
      keep = {
        daily = mkOption {
          type = types.int;
          default = 7;
          description = "Number of daily backups to keep";
        };

        weekly = mkOption {
          type = types.int;
          default = 4;
          description = "Number of weekly backups to keep";
        };

        monthly = mkOption {
          type = types.int;
          default = 6;
          description = "Number of monthly backups to keep";
        };
      };
    };

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = "Systemd calendar expression for backup schedule";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "SSH private key file for remote repository access";
    };

    remotePath = mkOption {
      type = types.nullOr types.str;
      default = "/usr/bin/borg";
      description = "Path to borg executable on remote server (for SSH repos)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ borgbackup ];

    services.borgbackup.jobs."system" = {
      paths = cfg.paths;
      exclude = cfg.exclude;
      repo = cfg.repository;
      encryption = {
        mode = cfg.encryption.mode;
        passCommand = if cfg.encryption.passphraseFile != null
          then "cat ${cfg.encryption.passphraseFile}"
          else null;
      };
      environment = mkIf (cfg.sshKeyFile != null) {
        BORG_RSH = "ssh -i ${cfg.sshKeyFile} -o StrictHostKeyChecking=accept-new";
      };
      compression = "auto,zstd";
      startAt = cfg.schedule;
      remotePath = cfg.remotePath;
      prune.keep = {
        daily = cfg.prune.keep.daily;
        weekly = cfg.prune.keep.weekly;
        monthly = cfg.prune.keep.monthly;
      };
      # Extra borg create arguments
      extraCreateArgs = "--stats --show-rc";
    };
  };
}
