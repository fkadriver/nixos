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
      default = "/run/current-system/sw/bin/borg";
      description = "Path to borg executable on remote server (for SSH repos)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ borgbackup ];

    # Wazuh integration: deploy status reporter script and its config.
    # wazuh-logcollector runs the command as root (inside the wazuh FHS env,
    # which bind-mounts the real /), so it can reach /run/current-system/sw/bin
    # for borgbackup and read the SSH key and passphrase files.
    systemd.tmpfiles.rules = [
      "d /usr/local/bin 0755 root root -"
      "L+ /usr/local/bin/wazuh-borg-status - - - - ${pkgs.writeShellScript "wazuh-borg-status" ''
        set -euo pipefail
        export PATH="/run/current-system/sw/bin:$PATH"

        CONF=/etc/wazuh/borg.conf
        # set -a exports all variables defined during source so borg subprocess sees them
        # shellcheck source=/dev/null
        set -a; [ -f "$CONF" ] && source "$CONF"; set +a

        REPO="''${BORG_REPO:-}"
        STALE_HOURS="''${BORG_STALE_HOURS:-25}"

        if [ -z "$REPO" ]; then
            echo "borg_backup: status=ERROR repo=unset error=BORG_REPO_not_configured"
            exit 0
        fi

        if ! command -v borg &>/dev/null; then
            echo "borg_backup: status=ERROR repo=''${REPO} error=borg_not_found"
            exit 0
        fi

        LAST=$(borg list --last 1 --format '{archive}|{start:%Y-%m-%dT%H:%M:%S}' "$REPO" 2>&1) || {
            ERR=$(printf '%s' "$LAST" | head -1 | tr -cs '[:alnum:]_.-' '_' | cut -c1-60)
            echo "borg_backup: status=ERROR repo=''${REPO} error=''${ERR}"
            exit 0
        }

        if [ -z "$LAST" ]; then
            echo "borg_backup: status=EMPTY repo=''${REPO} error=no_archives"
            exit 0
        fi

        ARCHIVE=$(printf '%s' "$LAST" | cut -d'|' -f1)
        START=$(printf '%s' "$LAST" | cut -d'|' -f2)

        START_EPOCH=$(date -d "''${START/T/ }" +%s 2>/dev/null) || START_EPOCH=0
        AGE_H=$(( ($(date +%s) - START_EPOCH) / 3600 ))

        DURATION=$(borg info "''${REPO}::''${ARCHIVE}" --format '{duration:.0f}' 2>/dev/null || echo "0")

        if [ "$AGE_H" -gt "$STALE_HOURS" ]; then
            STATUS=STALE
        else
            STATUS=OK
        fi

        echo "borg_backup: status=''${STATUS} repo=''${REPO} archive=''${ARCHIVE} start=''${START} duration=''${DURATION}s age=''${AGE_H}h"
      ''}"
    ];

    environment.etc."wazuh/borg.conf" = {
      mode = "0400";
      text = ''
        BORG_REPO="${cfg.repository}"
      '' + lib.optionalString (cfg.encryption.passphraseFile != null) ''
        BORG_PASSCOMMAND="cat ${cfg.encryption.passphraseFile}"
      '' + lib.optionalString (cfg.sshKeyFile != null) ''
        BORG_RSH="ssh -i ${cfg.sshKeyFile} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes"
      '' + lib.optionalString (cfg.remotePath != null) ''
        BORG_REMOTE_PATH="${cfg.remotePath}"
      '';
    };

    # Pin the backup server's host key declaratively so rebuilds are sufficient
    # after a server reinstall — no manual ssh-keygen -R on each client. The
    # borg job's ssh ignores per-user known_hosts (stale entries would
    # otherwise fail the CHANGED-key check) and trusts only this pin.
    programs.ssh.knownHosts."nas01.warthog-royal.ts.net".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrBHn7I+Zd1FGvi4L3hLzxJoRoydTKiDDKJ4Ivg1x2N";

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
      environment = mkMerge [
        { BORG_RELOCATED_REPO_ACCESS_IS_OK = "yes"; }
        (mkIf (cfg.sshKeyFile != null) {
          BORG_RSH = "ssh -i ${cfg.sshKeyFile} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes";
        })
        (mkIf (cfg.remotePath != null) {
          BORG_REMOTE_PATH = cfg.remotePath;
        })
      ];
      compression = "auto,zstd";
      startAt = cfg.schedule;
      prune.keep = {
        daily = cfg.prune.keep.daily;
        weekly = cfg.prune.keep.weekly;
        monthly = cfg.prune.keep.monthly;
      };
      # Extra borg create arguments
      extraCreateArgs = "--stats --show-rc";
    };

    # Ensure borg runs after bitwarden has synced secrets (passphrase file)
    systemd.services."borgbackup-job-system" = {
      after = [ "bitwarden-secrets-sync.service" ];
      wants = [ "bitwarden-secrets-sync.service" ];
    };
  };
}
