{ inputs, ... }@flakeContext:
let
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
          temps = "echo '=== CPU Temps ===' && sensors 2>/dev/null || echo '(run: sudo sensors-detect)'; echo ''; echo '=== Drive Temps ===' && for d in /dev/sd?; do echo -n \"$d: \"; sudo hddtemp -u C $d 2>/dev/null || sudo smartctl -A $d | grep -i 'temperature\\|194'; done";
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
        };
      };

      # ZFS: pool "pool" (raidz1, 3x HGST 4TB) created on Ubuntu, re-imported here.
      # First boot after reinstall needs a manual `zpool import -f pool`.
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;
      boot.zfs.extraPools = [ "pool" ];
      services.zfs.autoScrub.enable = true;
      services.zfs.trim.enable = true;

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
        hddtemp
        smartmontools
        zfs
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

      services.smartd.enable = true;

      # Drive temperature tools without password (temps alias)
      security.sudo.extraRules = [
        {
          users = [ "scott" ];
          commands = [
            { command = "/run/current-system/sw/bin/hddtemp"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/smartctl"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
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
            "/pool:/pool:ro"
            "/mnt:/mnt:ro"
          ];
          extraOptions = [ "--network=host" ];
        };
      };
      # The vendor cron daemon occasionally exits 0 on its own (scheduler bug:
      # "Argument \"*\" isn't numeric" warnings, then a clean exit); the default
      # on-failure policy leaves the service dead and the device offline.
      systemd.services.docker-idrive360.serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = lib.mkForce "60s";
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
