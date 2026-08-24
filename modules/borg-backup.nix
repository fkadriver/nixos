{ inputs, ... }@flakeContext:
{ config, lib, pkgs, options, ... }:

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

    remotePath = mkOption {
      type = types.nullOr types.str;
      default = "/run/current-system/sw/bin/borg";
      description = "Path to borg executable on remote server (for SSH repos)";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "SSH private key file for remote repository access";
    };

    preHook = mkOption {
      type = types.lines;
      default = "";
      description = "Shell commands run before the backup (e.g. to freeze a live disk for consistent backup).";
    };

    postHook = mkOption {
      type = types.lines;
      default = "";
      description = "Shell commands run after the backup, on both success and failure (e.g. to thaw a disk frozen in preHook).";
    };

    restoreTest = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Weekly canary restore-verification job. A small canary file is refreshed
          before every backup (via the job preHook); the test then deletes the local
          canary and restores it from the latest archive, proving the repo is
          actually restorable. Result is logged in the same `borg_...:` line format
          as the status probe and tailed into Wazuh.
        '';
      };

      canaryFile = mkOption {
        type = types.str;
        default = "/var/lib/borg-restore/canary";
        description = ''
          Canary file path. Its parent directory is added to the backup `paths`
          automatically, so the restore test works on any host that enables borg
          without further configuration.
        '';
      };

      schedule = mkOption {
        type = types.str;
        default = "Sun *-*-* 04:00:00";
        description = "systemd OnCalendar expression for the restore test (default: weekly, Sunday 04:00, after the nightly backup).";
      };

      logFile = mkOption {
        type = types.str;
        default = "/var/log/borg-restore.log";
        description = "Log file the restore test appends to; registered as a Wazuh localfile so results ship to the manager.";
      };
    };
  };

  config = mkIf cfg.enable (
   let
    canaryFile = cfg.restoreTest.canaryFile;
    canaryDir  = builtins.dirOf canaryFile;
    logFile    = cfg.restoreTest.logFile;

    # Self-contained restore verification: delete the live canary, recover it from
    # the newest archive, verify, and put it back. Reads the same /etc/wazuh/borg.conf
    # the status probe uses (BORG_REPO/PASSCOMMAND/RSH/REMOTE_PATH). Never exits
    # non-zero on a backup problem — it always emits one machine-parsable line so
    # Wazuh sees OK *and* failures.
    restoreTestScript = pkgs.writeShellScript "borg-restore-test" ''
      set -uo pipefail
      export PATH="/run/current-system/sw/bin:$PATH"
      export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

      CONF=/etc/wazuh/borg.conf
      # set -a so sourced BORG_* vars are exported to the borg subprocess
      # shellcheck source=/dev/null
      set -a; [ -f "$CONF" ] && . "$CONF"; set +a

      REPO="''${BORG_REPO:-${cfg.repository}}"
      CANARY="${canaryFile}"
      LOG="${logFile}"
      HOST="${config.networking.hostName}"

      mkdir -p "$(dirname "$LOG")"
      emit() {
        echo "$(date '+%b %e %H:%M:%S') $HOST borg_restore: $1" >> "$LOG"
        echo "borg_restore: $1"
      }

      if ! command -v borg >/dev/null 2>&1; then
        emit "status=ERROR repo=$REPO error=borg_not_found"; exit 0
      fi

      LAST=$(borg list --last 1 --format '{archive}' "$REPO" 2>&1) || {
        ERR=$(printf '%s' "$LAST" | head -1 | tr -cs '[:alnum:]_.-' '_' | cut -c1-60)
        emit "status=ERROR repo=$REPO error=$ERR"; exit 0
      }
      if [ -z "$LAST" ]; then
        emit "status=ERROR repo=$REPO error=no_archives"; exit 0
      fi

      # Preserve the current canary so a failed extract can be rolled back.
      BEFORE=""; [ -f "$CANARY" ] && BEFORE=$(cat "$CANARY" 2>/dev/null || true)
      restore_before() {
        if [ -n "$BEFORE" ]; then
          mkdir -p "$(dirname "$CANARY")"
          printf '%s\n' "$BEFORE" > "$CANARY"
        fi
      }

      # Delete-then-restore: remove the live canary and recover it from the archive.
      rm -f "$CANARY"
      TMP=$(mktemp -d)
      trap 'rm -rf "$TMP"' EXIT
      REL="''${CANARY#/}"

      if ! ( cd "$TMP" && borg extract "$REPO::$LAST" "$REL" ) 2>"$TMP/err"; then
        ERR=$(head -1 "$TMP/err" 2>/dev/null | tr -cs '[:alnum:]_.-' '_' | cut -c1-60)
        restore_before
        emit "status=ERROR repo=$REPO archive=$LAST error=extract_failed:$ERR"; exit 0
      fi

      EXTRACTED="$TMP/$REL"
      if [ ! -f "$EXTRACTED" ]; then
        restore_before
        emit "status=ERROR repo=$REPO archive=$LAST error=canary_absent_in_archive"; exit 0
      fi

      # Complete the round-trip: put the recovered canary back in place.
      mkdir -p "$(dirname "$CANARY")"
      cp "$EXTRACTED" "$CANARY"

      if head -1 "$EXTRACTED" | ${pkgs.gnugrep}/bin/grep -q '^borg-restore-canary$'; then
        WRITTEN=$(${pkgs.gnugrep}/bin/grep '^written=' "$EXTRACTED" | cut -d= -f2)
        AGE_H=0
        [ -n "''${WRITTEN:-}" ] && AGE_H=$(( ( $(date +%s) - WRITTEN ) / 3600 ))
        emit "status=OK repo=$REPO archive=$LAST verify=match canary_age=''${AGE_H}h"
      else
        emit "status=ERROR repo=$REPO archive=$LAST verify=mismatch"
      fi
    '';
   in
   lib.recursiveUpdate {
    environment.systemPackages = with pkgs; [ borgbackup ];

    environment.shellAliases =
      let
        borgEnvStr = concatStringsSep " " (filter (s: s != "") [
          (optionalString (cfg.sshKeyFile != null)
            ''BORG_RSH="ssh -i ${cfg.sshKeyFile} -o StrictHostKeyChecking=accept-new"'')
          (optionalString (cfg.encryption.passphraseFile != null)
            ''BORG_PASSCOMMAND="cat ${cfg.encryption.passphraseFile}"'')
          (optionalString (cfg.remotePath != null)
            ''BORG_REMOTE_PATH=${cfg.remotePath}'')
        ]);
        borgCmd = op: "sudo env ${borgEnvStr} borg ${op} ${cfg.repository}";
      in {
        borg-status = "sudo systemctl status borgbackup-job-system.service";
        borg-logs   = "sudo journalctl -u borgbackup-job-system.service -n 50";
        borg-timer  = "systemctl list-timers | grep borg";
        borg-run    = "sudo systemctl start borgbackup-job-system.service";
        # One-shot test: runs the same read-only status probe Wazuh polls hourly
        # (checks the repo is reachable and the last archive isn't stale) and
        # prints the result immediately instead of waiting for the next check-in.
        borg-test   = "sudo /usr/local/bin/wazuh-borg-status";
        borg-list   = borgCmd "list";
        borg-info   = borgCmd "info";
        borg-check  = borgCmd "check";
        borg-unlock = borgCmd "break-lock";
      };

    # Wazuh integration: deploy status reporter script and its config.
    # wazuh-logcollector runs the command as root (inside the wazuh FHS env,
    # which bind-mounts the real /), so it can reach /run/current-system/sw/bin
    # for borgbackup and read the SSH key and passphrase files.
    systemd.tmpfiles.rules = [
      "d /usr/local/bin 0755 root root -"
    ] ++ optional cfg.restoreTest.enable
      # borgbackup-job-system runs under ProtectSystem=strict, so canaryDir must
      # both exist before the unit starts (ReadWritePaths doesn't create it —
      # see the readWritePaths option below) and be pre-created here rather than
      # by preHook's own `mkdir -p`, which runs too late, inside the already
      # read-only-sandboxed process.
      "d ${canaryDir} 0700 root root -"
    ++ [
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

        # Duration + size stats from borg info (second borg call; acceptable for hourly cadence).
        # original_size/compressed_size/deduplicated_size are raw bytes straight from
        # --json, so (unlike IDrive360's size_backed_up) no unit-parsing hack is needed.
        INFO_JSON=$(borg info --json "''${REPO}::''${ARCHIVE}" 2>/dev/null) || INFO_JSON=""

        DURATION="0"
        ORIGINAL_SIZE="unknown"
        COMPRESSED_SIZE="unknown"
        DEDUPLICATED_SIZE="unknown"
        if [ -n "$INFO_JSON" ]; then
            DURATION=$(jq -r '.archives[0].duration // 0 | floor' <<<"$INFO_JSON" 2>/dev/null || echo "0")
            ORIGINAL_SIZE=$(jq -r '.archives[0].stats.original_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
            COMPRESSED_SIZE=$(jq -r '.archives[0].stats.compressed_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
            DEDUPLICATED_SIZE=$(jq -r '.archives[0].stats.deduplicated_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
        fi

        if [[ "$ARCHIVE" == *.failed ]]; then
            echo "borg_backup: status=ERROR repo=''${REPO} archive=''${ARCHIVE} start=''${START} duration=''${DURATION}s age=''${AGE_H}h original_size=''${ORIGINAL_SIZE} compressed_size=''${COMPRESSED_SIZE} deduplicated_size=''${DEDUPLICATED_SIZE} error=archive_marked_failed"
            exit 0
        fi

        if [ "$AGE_H" -gt "$STALE_HOURS" ]; then
            STATUS=STALE
        else
            STATUS=OK
        fi

        echo "borg_backup: status=''${STATUS} repo=''${REPO} archive=''${ARCHIVE} start=''${START} duration=''${DURATION}s age=''${AGE_H}h original_size=''${ORIGINAL_SIZE} compressed_size=''${COMPRESSED_SIZE} deduplicated_size=''${DEDUPLICATED_SIZE}"
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
    # otherwise fail the CHANGED-key check) and trusts only this pin. If nas01
    # gets reinstalled, update the publicKey below and rebuild every client
    # (tailscale-ssh's auto-rekey-detection was tried and reverted — see git
    # history around 2026-08-23 — for less overall complexity, since Syncthing
    # already provides a second, independent copy of critical data).
    #
    # Only the borg job's plain OpenSSH relies on this pin now, and it connects
    # via the FQDN (ssh://scott@nas01.warthog-royal.ts.net/...). The helper
    # scripts (host-status.sh, sync-nixos-hosts.sh) all use `tailscale ssh`,
    # which verifies keys via Tailscale's coordination server and doesn't touch
    # known_hosts at all. The bare "nas01" hostName is kept as a harmless alias
    # in case anything is ever pointed at the short name.
    programs.ssh.knownHosts."nas01.warthog-royal.ts.net" = {
      hostNames = [ "nas01.warthog-royal.ts.net" "nas01" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIZPV9hUboOiTvvmg6KnrjxP1c9EfPMIKjwDJmEty3P";
    };

    services.borgbackup.jobs."system" = {
      # Auto-include the canary dir so the restore test works regardless of `paths`.
      paths = cfg.paths ++ optional cfg.restoreTest.enable canaryDir;
      exclude = cfg.exclude;
      repo = cfg.repository;
      # The job runs under ProtectSystem=strict; canaryDir must be listed here
      # or preHook's write to it hits a read-only filesystem (confirmed: this
      # broke nightly backups fleet-wide for two nights before being caught —
      # the mkdir failure aborts the whole job, not just the canary refresh).
      # The directory itself is pre-created by the tmpfiles rule above, since
      # ReadWritePaths requires the path to already exist.
      readWritePaths = optional cfg.restoreTest.enable canaryDir;
      # Refresh the canary before every backup so the newest archive always holds a
      # current one, then run any user-supplied preHook.
      preHook = (optionalString cfg.restoreTest.enable ''
        mkdir -p ${canaryDir}
        {
          echo "borg-restore-canary"
          echo "host=${config.networking.hostName}"
          echo "written=$(date +%s)"
          echo "token=$(date +%s%N)-$$"
        } > ${canaryFile}
      '') + cfg.preHook;
      postHook = cfg.postHook;
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
      failOnWarnings = false;
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

    # Weekly restore verification (canary round-trip). Self-contained: enabling
    # services.borg-backup is all a host needs — the timer, script, and Wazuh
    # localfile are all provided here.
    systemd.services.borg-restore-test = mkIf cfg.restoreTest.enable {
      description = "Borg restore verification (canary round-trip) for ${cfg.repository}";
      # Order after wazuh-agent so its logcollector is already tailing borg-restore.log
      # when we append. Wazuh syslog localfiles read from EOF and never backfill, so a
      # line written before logcollector opens the file would be silently dropped —
      # which is exactly why a freshly-onboarded host's first result never shipped until
      # a manual re-run. (after= on a nonexistent unit is ignored on non-wazuh hosts.)
      after = [ "network-online.target" "bitwarden-secrets-sync.service" "wazuh-agent.service" ];
      wants = [ "network-online.target" "bitwarden-secrets-sync.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = toString restoreTestScript;
      };
    };

    systemd.timers.borg-restore-test = mkIf cfg.restoreTest.enable {
      description = "Schedule weekly Borg restore verification";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Weekly schedule, plus a boot-time run so a newly-onboarded (or freshly-rebuilt)
        # host emits a live result once logcollector is tailing, rather than waiting up to
        # a week for the first line to reach Wazuh. network-online + the wazuh-agent
        # ordering above keep this from firing before the repo is reachable / logcollector
        # is up. Persistent still catches up a missed weekly run.
        OnCalendar = cfg.restoreTest.schedule;
        OnBootSec = "5min";
        Persistent = true;
      };
    };

    # Ship restore-test results to Wazuh by tailing its log (same mechanism as the
    # status probe's log on nas01). Merges with any host-level extraLocalFiles.
    # Guarded on the option existing — hosts without wazuh-agent imported (e.g.
    # OTworkstation) can still use borg-backup, they just skip Wazuh shipping.
  } (optionalAttrs (options.services ? wazuh-agent) {
    # `//` here would shallow-clobber the whole `services` key from the
    # attrset above (wiping services.borgbackup.jobs."system" on every host
    # with wazuh-agent imported — confirmed broke nightly backups fleet-wide
    # for two days, 2026-08-23/24). lib.recursiveUpdate merges nested keys
    # instead of replacing the top-level attribute wholesale.
    services.wazuh-agent.extraLocalFiles = mkIf cfg.restoreTest.enable [
      { location = logFile; logFormat = "syslog"; }
    ];
   }));
}
