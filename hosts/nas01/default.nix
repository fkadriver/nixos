{ inputs, ... }@flakeContext:
let
  # Writes one syslog-format line to /var/log/idrive360-status.log every run.
  # Uses a glob for the device hash so it survives re-registration.
  idrive360StatusScript = pkgs: pkgs.writeShellScript "idrive360-status" ''
    set -euo pipefail
    STATUS_FILE=$(${pkgs.findutils}/bin/find /var/lib/idrive360/opt/idriveIt/user_profile/scott \
      -name "lastBackupStatus.txt" 2>/dev/null | head -1)
    LOG=/var/log/idrive360-status.log

    if [ -z "$STATUS_FILE" ]; then
      echo "$(date '+%b %d %H:%M:%S') nas01 idrive360-status: ERROR no status file found" >> "$LOG"
      exit 0
    fi

    STATUS=$(${pkgs.jq}/bin/jq -r '.last_backup_status.status // "unknown"' "$STATUS_FILE")
    FILENAME=$(${pkgs.jq}/bin/jq -r '.last_backup_status.filename // "unknown"' "$STATUS_FILE")
    JOBTYPE=$(${pkgs.jq}/bin/jq -r '.last_backup_status.jobType // "unknown"' "$STATUS_FILE")
    echo "$(date '+%b %d %H:%M:%S') nas01 idrive360-status: status=$STATUS job=$FILENAME type=$JOBTYPE" >> "$LOG"
  '';

  # Called by smartd via -M exec when a SMART failure is detected.
  smartdAlertScript = pkgs: pkgs.writeShellScript "smartd-alert" ''
    LOG=/var/log/smartd-alerts.log
    echo "$(date '+%b %d %H:%M:%S') nas01 smartd: ALERT device=''${SMARTD_DEVICE:-unknown} type=''${SMARTD_FAILTYPE:-unknown} msg=''${SMARTD_MESSAGE:-}" >> "$LOG"
  '';

  # Checks each borg repo's index mtime; logs OK or STALE for Wazuh.
  borgStatusScript = pkgs: pkgs.writeShellScript "borg-status" ''
    LOG=/var/log/borg-status.log
    REPOS_DIR=/pool/borg
    STALE_HOURS=48
    if [ ! -d "$REPOS_DIR" ]; then
      echo "$(date '+%b %d %H:%M:%S') nas01 borg-status: ERROR repos_dir not found" >> "$LOG"
      exit 0
    fi
    for repo in "$REPOS_DIR"/*/; do
      [ -d "$repo" ] || continue
      host=$(basename "$repo")
      mod=$(${pkgs.coreutils}/bin/stat -c "%Y" "$repo"index.* 2>/dev/null | sort -n | tail -1)
      if [ -z "$mod" ]; then
        echo "$(date '+%b %d %H:%M:%S') nas01 borg-status: host=$host status=NOINDEX" >> "$LOG"
        continue
      fi
      now=$(${pkgs.coreutils}/bin/date +%s)
      age_h=$(( (now - mod) / 3600 ))
      if [ "$age_h" -ge "$STALE_HOURS" ]; then
        status=STALE
      else
        status=OK
      fi
      echo "$(date '+%b %d %H:%M:%S') nas01 borg-status: host=$host status=$status age_hours=$age_h" >> "$LOG"
    done
  '';

  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.vscode-server
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.syncthing-declarative
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
    ];

    config = {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      # NAS server aliases (moved from the Ubuntu-era standalone home-manager config)
      home-manager.users.scott = {
        programs.bash.shellAliases = {
          # Borg server overview (no passphrase needed — uses filesystem timestamps)
          borg-repos = ''echo "=== Borg Repos ===" && for repo in /pool/borg/*/; do host=$(basename "$repo"); last=$(stat -c "%y" "''${repo}"index.* 2>/dev/null | sort | tail -1 | cut -d'.' -f1); size=$(du -sh "''${repo}" 2>/dev/null | cut -f1); printf "%-20s %-8s %s\n" "$host" "''${size:--}" "''${last:-no backups}"; done'';

          # ZFS
          zs    = "zpool status";
          zsv   = "zpool status -v";
          zpl   = "zpool list";
          zl    = "zfs list";
          zla   = "zfs list -t all";
          zls   = "zfs list -t snapshot";
          zll   = "zfs list -o name,used,avail,refer,mountpoint";
          zc    = "zfs create -o compression=lz4";
          zd    = "zfs destroy";
          zdr   = "zfs destroy -r";

          # Temperature monitoring
          temps = ''echo '=== CPU Temps (°F) ===' && sensors -f 2>/dev/null | grep -E ':.*°F' || echo '(run: sudo sensors-detect)'; echo ""; echo '=== Drive Temps (°F) ==='; for d in /dev/sd?; do C=$(sudo smartctl -A "$d" 2>/dev/null | awk '/^[[:space:]]*19[04] /{print $10}' | head -1); if [ -n "$C" ]; then printf "%s: %d°F\n" "$d" "$((C * 9 / 5 + 32))"; else printf "%s: N/A\n" "$d"; fi; done'';

          # IDrive360 monitoring
          idrive-docker  = "journalctl -u docker-idrive360 -f";
          idrive-log     = ''tail -f "$(ls -t /var/lib/idrive360/opt/idriveIt/user_profile/scott/*/Backup/DefaultBackupSet/LOGS/* 2>/dev/null | head -1)"'';
          idrive-restart = "sudo systemctl restart docker-idrive360";
          idrive-status  = ''
            echo "=== Container ===" && docker ps --filter name=idrive360 --format "{{.Status}}" | grep . || echo "NOT RUNNING";
            LATEST=$(ls -t /var/lib/idrive360/opt/idriveIt/user_profile/scott/*/Backup/DefaultBackupSet/LOGS/* 2>/dev/null | head -1);
            echo "=== Latest log: $(basename "$LATEST") ($(stat -c '%y' "$LATEST" 2>/dev/null | cut -d. -f1)) ===";
            tail -6 "$LATEST" 2>/dev/null
          '';
        };
        programs.bash.initExtra = ''
          # Borg server functions — take hostname as argument
          # Usage: borg-ls latitude | borg-check vm01 | borg-unlock airbook.local
          # unalias first: shell-aliases.nix defines client-side borg-check/borg-unlock
          # aliases (ssh to nas01), which break these function definitions at parse time
          unalias borg-check borg-unlock 2>/dev/null
          BORG_REPOS=/pool/borg
          borg-ls()     { sudo borg list       "$BORG_REPOS/$1"; }
          borg-check()  { sudo borg check      "$BORG_REPOS/$1"; }
          borg-unlock() { sudo borg break-lock "$BORG_REPOS/$1"; }
        '';
      };

      networking = {
        hostName = "nas01";
        # Required for ZFS pool import; arbitrary but must never change
        hostId = "9ede3d5d";
        networkmanager.enable = true;
        firewall = {
          # Samba/NFS for LAN clients (exports/smb.conf restrict per-share access);
          # tailscale0 is trusted via modules/tailscale.nix
          allowedTCPPorts = [ 111 139 445 2049 4000 4001 20048 ];
          allowedUDPPorts = [ 111 137 138 2049 4000 4001 20048 ];
          interfaces."tailscale0".allowedTCPPorts = [ 8384 ];
        };
      };

      # Syncthing GUI reachable over Tailscale (firewall restricts 8384 to tailscale0)
      services.syncthing.guiAddress = lib.mkForce "0.0.0.0:8384";

      # ZFS: pool "pool" (raidz1, 3x HGST 4TB) created on Ubuntu, re-imported here.
      # First boot after reinstall needs a manual `zpool import -f pool`.
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;
      boot.zfs.extraPools = [ "pool" ];
      services.zfs.autoScrub.enable = true;
      services.zfs.trim.enable = true;
      services.zfs.zed = {
        enableMail = false;
        settings = {
          ZED_NOTIFY_VERBOSE = 1;
          ZED_SYSLOG_PRI = "daemon.notice";
        };
      };

      # WD 18TB drive — FAILING as of 2026-07 (kernel dropped both mounts on the
      # old Ubuntu install). Kept with nofail for salvage attempts; borg repos
      # moved to the redundant ZFS pool at /pool/borg. Remove when drive is pulled.
      fileSystems."/mnt/wd18t_1" = {
        device = "/dev/disk/by-uuid/02d115cd-4e24-4dc9-adb9-7ea7ae4fdf20";
        fsType = "ext4";
        options = [ "nofail" "x-systemd.device-timeout=5" ];
      };
      fileSystems."/mnt/wd18t_3" = {
        device = "/dev/disk/by-uuid/886e681a-20b4-40bb-a408-060e63c4efe5";
        fsType = "ext4";
        options = [ "nofail" "x-systemd.device-timeout=5" ];
      };

      # SSH access (headless server; borg clients connect as scott)
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };

      security.sudo.wheelNeedsPassword = false;

      # Samba: data share + read-only borg repo browsing
      # (borg clients back up via SSH, not SMB)
      users.groups.nas = { };
      users.users.scott.extraGroups = [ "nas" ];
      services.samba = {
        enable = true;
        settings = {
          global = {
            workgroup = "WORKGROUP";
            "server string" = "nas01";
            "server role" = "standalone server";
            security = "user";
            "map to guest" = "never";
            "hosts allow" = "192.168.1.0/24 100.64.0.0/10 127.0.0.1";
            "hosts deny" = "ALL";
            "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
            "use sendfile" = "yes";
            "aio read size" = "0";
            "aio write size" = "0";
            "multicast dns register" = "yes";
          };
          data = {
            comment = "NAS Data";
            path = "/pool/data";
            "valid users" = "scott";
            "read only" = "no";
            browsable = "yes";
            "create mask" = "0664";
            "directory mask" = "0775";
            "force group" = "nas";
          };
          borg = {
            comment = "Borg Backup Repositories";
            path = "/pool/borg";
            "valid users" = "scott";
            "read only" = "yes";
            browsable = "yes";
          };
        };
      };

      # NFS exports (LAN + Tailscale, same as Ubuntu-era /etc/exports)
      services.nfs.server = {
        enable = true;
        # Fixed ports so the firewall rules above cover NFSv3
        statdPort = 4000;
        lockdPort = 4001;
        mountdPort = 20048;
        exports = ''
          /pool/data    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

          # SANS course materials: LAN read-only, Tailscale read/write
          /pool/shares/SANS    192.168.0.0/16(sync,wdelay,hide,no_subtree_check,sec=sys,ro,secure,no_root_squash,no_all_squash)
          /pool/shares/SANS    100.64.0.0/10(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)

          # Photos: Tailscale only
          /pool/shares/photos    100.64.0.0/10(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)
        '';
      };

      # Borg server side: clients invoke borg over SSH as scott
      environment.systemPackages = with pkgs; [
        borgbackup
        hd-idle
        smartmontools
        zfs
        # Remote desktop session
        openbox
        firefox
        xterm
      ];
      systemd.tmpfiles.rules = [
        "d /pool/borg 0750 scott users -"
        "d /var/lib/idrive360/opt  0755 root root -"
        "d /var/lib/idrive360/seed 0755 root root -"
      ];

      # Drive spindown. by-id paths instead of sdX (assignments shift on reboot).
      # ZFS pool drives: 30 min; borg drive: 10 min; OS SSD excluded (-i 0 default).
      systemd.services.hd-idle = {
        description = "Spin down idle hard drives";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.hd-idle}/bin/hd-idle"
            "-i 0"
            "-a /dev/disk/by-id/ata-HGST_HDS724040ALE640_PK1301PAJ2480X -i 1800"
            "-a /dev/disk/by-id/ata-HGST_HDS724040ALE640_PK2331PAJEL1NT -i 1800"
            "-a /dev/disk/by-id/ata-HGST_HDS724040ALE640_PK1301PAJ44X6S -i 1800"
            "-a /dev/disk/by-id/ata-WDC_WD180EDGZ-11BLDS0_8LHT7HVR -i 600"
          ];
          Restart = "on-failure";
        };
      };

      services.smartd = {
        enable = true;
        defaults.monitored = "-a -M exec ${smartdAlertScript pkgs}";
      };

      # Drive temperature tools without password (temps alias)
      security.sudo.extraRules = [
        {
          users = [ "scott" ];
          commands = [
            { command = "/run/current-system/sw/bin/smartctl"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];

      # Remote desktop (xrdp): headless — no local display manager.
      # Connect via any RDP client to nas01:3389 (or nas01.warthog-royal.ts.net:3389).
      # Right-click desktop for menu; use Firefox to reach the IDrive360 web console.
      services.xserver.enable = true;
      services.xserver.displayManager.lightdm.enable = false;
      services.xrdp = {
        enable = true;
        defaultWindowManager = "${pkgs.writeShellScript "openbox-session" ''
          exec ${pkgs.dbus}/bin/dbus-launch --exit-with-session ${pkgs.openbox}/bin/openbox-session
        ''}";
        openFirewall = true;
      };
      environment.etc."xdg/openbox/menu.xml".text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <openbox_menu xmlns="http://openbox.org/"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="http://openbox.org/ file:///usr/share/openbox/menu.xsd">
        <menu id="root-menu" label="nas01">
          <item label="Firefox">
            <action name="Execute"><execute>firefox</execute></action>
          </item>
          <item label="Terminal">
            <action name="Execute"><execute>xterm</execute></action>
          </item>
          <separator/>
          <menu id="client-list-menu"/>
          <separator/>
          <item label="Reconfigure">
            <action name="Reconfigure"/>
          </item>
          <item label="Log Out">
            <action name="Exit"/>
          </item>
        </menu>
        </openbox_menu>
      '';

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
        extraLocalFiles = [
          { location = "/var/log/idrive360-status.log"; logFormat = "syslog"; }
          { location = "/var/log/smartd-alerts.log"; logFormat = "syslog"; }
          { location = "/var/log/borg-status.log"; logFormat = "syslog"; }
        ];
      };

      # IDrive360 backup status logger — writes one syslog line every 15 min so
      # Wazuh can alert on status=Failure without reading inside the container.
      systemd.services.idrive360-status = {
        description = "Log IDrive360 backup status for Wazuh";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = idrive360StatusScript pkgs;
        };
      };
      systemd.timers.idrive360-status = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "15min";
          Persistent = true;
        };
      };

      systemd.services.borg-status = {
        description = "Log Borg backup staleness for Wazuh";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = borgStatusScript pkgs;
        };
      };
      systemd.timers.borg-status = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "6h";
          Persistent = true;
        };
      };

      # IDrive360 cloud backup: vendor .deb self-updates and downloads its engine
      # at runtime, so it runs in an Ubuntu container instead of a Nix package
      # (prior packaging attempt archived in archive/pkgs/idrive-e360/).
      # State lives in /var/lib/idrive360/opt (seeded from the pre-rebuild backup);
      # /var/lib/idrive360/seed holds the installer .deb and rescued cron binary.
      # Backup set (web console) covers /pool, /mnt, /opt.
      environment.etc."idrive360/entrypoint.sh" = {
        source = ./idrive360-entrypoint.sh;
        mode = "0755";
      };
      virtualisation.oci-containers = {
        backend = "docker";
        containers.idrive360 = {
          image = "ubuntu:24.04";
          entrypoint = "/entrypoint.sh";
          volumes = [
            "/etc/idrive360/entrypoint.sh:/entrypoint.sh:ro"
            "/var/lib/idrive360/opt:/opt/IDrive360"
            "/var/lib/idrive360/seed:/seed:ro"
            # rslave: ZFS mount events at /pool and /mnt propagate into the
            # container after the pool imports, even if the container started first
            "/pool:/pool:ro,rslave"
            "/mnt:/mnt:ro,rslave"
          ];
          # --init: tini as PID 1 to reap the zombie children the vendor cron
          # daemon leaves behind
          extraOptions = [ "--network=host" "--init" ];
        };
      };
      # The vendor cron daemon occasionally exits 0 on its own (scheduler bug:
      # "Argument \"*\" isn't numeric" warnings, then a clean exit); the default
      # on-failure policy leaves the service dead and the device offline.
      # Start after ZFS so the pool is mounted before the container binds /pool.
      systemd.services.docker-idrive360 = {
        after = [ "zfs-import-pool.service" ];
        requires = [ "zfs-import-pool.service" ];
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = lib.mkForce "60s";
        };
      };

      system = {
        stateVersion = "25.11";
        nixos.label = "nas01";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
