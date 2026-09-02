{ inputs, ... }@flakeContext:
let
  # smartd + wazuh-smart-status are now provided fleet-wide by
  # modules/smart-monitor.nix (imported above) — was nas01-only inline here.

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
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.vscode-server
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.smart-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.syncthing-declarative
      inputs.self.nixosModules.fwupd
      inputs.self.nixosModules.nix-cache-proxy
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
    ];

    config = {
      # nas01 is headless (SSH/VNC-only, no console login or SDDM session), so
      # vscode-server.nix's PAM auto-unlock (wired to "login"/"sddm") never
      # fires here. Every SSH session then tries to prompt gnome-keyring to
      # unlock, which fails immediately (no display) and spams the journal.
      services.gnome.gnome-keyring.enable = lib.mkForce false;

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

          # IDrive360 — nas01-backup VM (Ubuntu 24.04 / QEMU/KVM)
          # VMs live in qemu:///system; LIBVIRT_DEFAULT_URI is set in initExtra below.
          idrive-status   = "virsh domstate nas01-backup --reason";
          idrive-ip       = "virsh domifaddr nas01-backup";
          idrive-start    = "sudo virsh start nas01-backup";
          idrive-stop     = "sudo virsh shutdown nas01-backup";
          idrive-ssh      = ''ssh scott@$(virsh domifaddr nas01-backup | awk '/ipv4/{print $4}' | cut -d/ -f1)'';
          idrive-console  = "sudo virsh console nas01-backup";
          # QEMU's graphical console (the guest's actual virtual monitor / lightdm
          # session, which auto-logs scott into LXDE at boot — no in-guest VNC
          # server anymore, that duplicate session caused PolicyKit "No session
          # for pid" failures). Reachable directly over tailscale (no SSH tunnel)
          # at nas01.warthog-royal.ts.net:5900 — listen is nas01's own tailscale
          # IP, gated by tailscale0 being a trustedInterfaces entry. Connect from
          # whatever tailnet device you're actually sitting at (e.g. on latitude:
          # krdc vnc://nas01.warthog-royal.ts.net:5900) — no VNC client needed
          # on nas01 itself.
          # Single-window remote view of just the IDrive360 GUI, no VNC — attaches over
          # SSH to the idrive360-xpra seamless session on the VM (same alias as
          # latitude/airbook-darwin).
          idrive-app      = "xpra attach ssh://scott@nas01-backup.warthog-royal.ts.net/100";
          # Restart the IDrive360 agent service inside the VM (over the tailnet —
          # the VM is its own tailnet node, same path latitude/airbook use).
          idrive-restart  = "ssh scott@nas01-backup.warthog-royal.ts.net sudo systemctl restart idrive360cron";
          # VM disk backup (Borg, local repo /pool/borg/nas01) — runs daily via
          # borgbackup-job-system.service; these are for on-demand use.
          idrive-vm-backup  = "sudo systemctl start borgbackup-job-system.service && sudo journalctl -u borgbackup-job-system.service -n 20 --no-pager";
          idrive-vm-list    = ''sudo env BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" borg list /pool/borg/nas01'';
          idrive-vm-restore = "sudo bash /etc/nas01-backup/vm-restore.sh";
        };
        programs.bash.initExtra = ''
          # virsh defaults to qemu:///session; VMs live in qemu:///system
          export LIBVIRT_DEFAULT_URI=qemu:///system

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
        # eno2 is the second port of the onboard Broadcom BCM5720 LOM,
        # unused (no cable). Explicitly unmanaged + forced down so it can't
        # silently join the network if a cable is ever plugged in later —
        # NetworkManager would otherwise auto-DHCP any interface it sees.
        networkmanager.unmanaged = [ "eno2" ];
        firewall = {
          # NFS for LAN clients (exports restrict per-share access);
          # tailscale0 is trusted via modules/tailscale.nix
          allowedTCPPorts = [ 111 2049 4000 4001 20048 ];
          allowedUDPPorts = [ 111 2049 4000 4001 20048 ];
          interfaces."tailscale0".allowedTCPPorts = [ 8384 ];
        };
      };

      # Syncthing GUI reachable over Tailscale (firewall restricts 8384 to tailscale0)
      services.syncthing.guiAddress = lib.mkForce "0.0.0.0:8384";

      # Syncthing GUI basic-auth (browser login only — syncthingtray's API-key
      # access on latitude/airbook is unaffected). Password lives in Bitwarden
      # ("syncthing" item), not the Nix store — see syncthing-declarative.nix.
      services.bitwarden.secrets.syncthing_gui_password = {
        name = "syncthing_gui_password";
        itemId = "0a30616d-a1dc-458b-bfd9-b4b001113d39";  # BW_Name: syncthing
        field = "password";
        mode = "0400";
        owner = "scott";
      };

      # In-band IPMI to the iDRAC8's management controller. Dell's iDRAC
      # Service Module (iSM) has no NixOS package (RPM/DEB-only, bundles a
      # kernel module built against specific distro kernels), so this
      # doesn't clear iDRAC's RAC0690 "Service Module not installed"
      # message or give in-band update/OS-name reporting — just local
      # sensor/SEL/power access via ipmitool.
      boot.kernelModules = [ "ipmi_si" "ipmi_devintf" "ipmi_msghandler" ];

      # iDRAC8's virtual console went "No Signal" partway through boot.
      # journalctl -k showed the kernel starting on the EFI GOP framebuffer
      # (simpledrm) then, ~1min later, mgag200 (the Matrox G200 chip iDRAC
      # itself uses for KVM/video capture) taking over and doing its own
      # modeset — a mode iDRAC's video-capture engine doesn't sync to
      # reliably. Blacklisting mgag200 keeps simpledrm driving the console
      # for the whole boot instead, which iDRAC displays fine (SSH/racadm
      # were unaffected either way — this is a physical/remote-KVM-only
      # symptom).
      boot.blacklistedKernelModules = [ "mgag200" ];

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

      users.users.scott.extraGroups = [ "libvirtd" "kvm" ];

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

      # Immich (migrated from vm01). NOT /pool/shares/photos — that's the
      # unrelated existing family-photos NFS export. This is a separate
      # dataset dedicated to the immich docker stack (uploads + postgres).
      #
      # One-time manual step before the first rebuild that references these
      # paths (dataset creation is imperative here, same as every other
      # dataset on "pool" — see docs/nas01.md, ZFS was never brought under
      # disko):
      #   sudo zfs create -o compression=lz4 pool/photos
      #   sudo zfs create -o recordsize=1M -o compression=off pool/photos/library
      #   sudo zfs create -o recordsize=16K -o compression=lz4 pool/photos/postgres
      #   sudo chown immich:immich pool/photos/library pool/photos/postgres
      #   sudo chmod 750 pool/photos/library pool/photos/postgres
      # (library holds already-compressed jpg/heic/mp4 — recordsize=1M and no
      # compression avoid wasting CPU re-compressing it; postgres wants a
      # small recordsize matching its page size. Ownership is chowned by hand,
      # not by a tmpfiles "z" rule — systemd-tmpfiles refuses to fix ownership
      # through /pool, since /pool itself is scott-owned rather than root, and
      # treats that as an unsafe path transition. Re-run the chown/chmod above
      # by hand if these datasets are ever recreated.)
      users.groups.immich = {};
      users.users.immich = {
        isSystemUser = true;
        group = "immich";
        home = "/home/users/immich";
        createHome = true;
        shell = pkgs.bash;
        extraGroups = [ "docker" ];
      };

      # Deploy the same GitHub deploy key vm01 uses (fetched into scott's
      # ~/.ssh by bitwarden-ssh-keys) so the immich user can clone/pull
      # git@github.com:fkadriver/immich-app.git on its own.
      system.activationScripts.immichSshGithub = lib.stringAfter [ "bitwarden-ssh-keys" "users" ] ''
        SSH_DIR=/home/users/immich/.ssh
        SRC_KEY=/home/scott/.ssh/id_ed25519_github

        if [ -f "$SRC_KEY" ]; then
          mkdir -p "$SSH_DIR"
          chmod 700 "$SSH_DIR"
          chown immich:immich "$SSH_DIR"

          cp "$SRC_KEY" "$SSH_DIR/id_ed25519_github"
          chmod 600 "$SSH_DIR/id_ed25519_github"
          chown immich:immich "$SSH_DIR/id_ed25519_github"

          cat > "$SSH_DIR/config" << 'EOF'
Host github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
          chmod 600 "$SSH_DIR/config"
          chown immich:immich "$SSH_DIR/config"
        else
          echo "Warning: $SRC_KEY not found — immich GitHub SSH key not installed" >&2
        fi
      '';

      # Immich Docker Compose stack. The repo itself
      # (git@github.com:fkadriver/immich-app.git) is cloned manually as the
      # immich user, same convention as unifi-docker/immich-ml-docker below —
      # Nix wires up the user/key/service but doesn't own the checkout:
      #   sudo -u immich git clone git@github.com:fkadriver/immich-app.git /home/users/immich/git/immich
      # .env (gitignored upstream) then needs UPLOAD_LOCATION=/pool/photos/library
      # and DB_DATA_LOCATION=/pool/photos/postgres, with PUID/PGID set to
      # `id immich` on this host (NOT vm01's — uids aren't pinned to match,
      # see users.users.immich above).
      systemd.services.immich-docker = {
        description = "Immich Docker Compose Stack";
        # wantedBy disabled — data migration from vm01 is paused. Re-enable
        # once library/postgres are populated and .env is confirmed correct.
        # wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/users/immich/git/immich";
          ExecStart = "${pkgs.docker}/bin/docker compose up -d";
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Borg server side: clients invoke borg over SSH as scott
      environment.systemPackages = with pkgs; [
        borgbackup
        hd-idle
        zfs
        ethtool
        ipmitool
        # QEMU/KVM: nas01-backup VM (IDrive360 backup agent)
        cloud-utils      # cloud-localds for building cloud-init ISOs
        xpra             # xpra client for idrive-app alias — single-window remote view of IDrive360
      ];
      # Force eno2 down at every network start (belt-and-suspenders with
      # networkmanager.unmanaged above — doesn't survive a driver reload,
      # hence re-applied here rather than set once).
      networking.localCommands = ''
        ${pkgs.iproute2}/bin/ip link set eno2 down 2>/dev/null || true
      '';
      systemd.tmpfiles.rules = [
        "d /pool/borg 0750 scott users -"
        "d /usr/local/bin 0755 root root -"
        "L+ /usr/local/bin/wazuh-zfs-pool-status - - - - ${pkgs.writeShellScript "wazuh-zfs-pool-status" (builtins.readFile ./wazuh-zfs-pool-status.sh)}"
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

      # Drive temperature tools without password (temps alias)
      security.sudo.extraRules = [
        {
          users = [ "scott" ];
          commands = [
            { command = "/run/current-system/sw/bin/smartctl"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
        extraLocalFiles = [
          { location = "/var/log/borg-status.log"; logFormat = "syslog"; }
        ];
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

      # IDrive360 cloud backup: runs in the nas01-backup QEMU/KVM VM (Ubuntu 24.04).
      # Set up once with:  sudo bash /etc/nas01-backup/setup.sh
      # The VM persists its disk across reboots — no re-registration needed.
      virtualisation.libvirtd = {
        enable = true;
        qemu.vhostUserPackages = [ pkgs.virtiofsd ];
        # nas01-backup uses virtiofs shares, which don't support save/restore —
        # managed-save on host shutdown leaves an unrestorable image (SIGPIPE on
        # resume). ACPI-shutdown the guest instead so it always cold boots.
        onShutdown = "shutdown";
        # Default is 300s. 2026-08-25: nas01-backup's guest agent didn't
        # respond to a shutdown request and the host sat waiting most of
        # the way to the full 5 minutes (looked hung, got power-cycled via
        # iDRAC before the timeout would've expired on its own). The guest
        # already tolerates an ungraceful stop by design (comment above),
        # so there's no reason to wait that long before giving up.
        shutdownTimeout = 60;
      };
      # VM definition and setup script deployed to /etc/nas01-backup/
      environment.etc."nas01-backup/domain.xml" = {
        source = ./nas01-backup-domain.xml;
        mode = "0644";
      };
      environment.etc."nas01-backup/setup.sh" = {
        source = ./nas01-backup-setup.sh;
        mode = "0755";
      };
      environment.etc."nas01-backup/vm-restore.sh" = {
        source = ./nas01-backup-vm-restore.sh;
        mode = "0755";
      };

      # nas01's own OS-disk data that can't be rebuilt from this flake: /home
      # and the nas01-backup VM disk (its IDrive360 registration/config).
      # Backed up locally to /pool (redundant ZFS raidz1), so it survives a
      # failure of nas01's OS SSD — see docs/nas01.md.
      #
      # The VM disk is only ever backed up in a frozen, consistent state:
      # preHook redirects its writes to a throwaway overlay (live, no VM
      # downtime) before borg reads it; postHook merges the overlay back.
      # Memory state is never involved — nas01-backup's virtiofs shares can't
      # save/restore that anyway (see the managed-save incident, 2026-07-28).
      services.borg-backup = {
        enable = true;
        repository = "/pool/borg/nas01";
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        paths = [
          "/home"
          "/var/lib/libvirt/images/nas01-backup.qcow2"
          "/var/lib/libvirt/images/nas01-backup-cidata.iso"
        ];
        preHook = ''
          OVERLAY=/var/lib/libvirt/images/nas01-backup.borgsnap.qcow2
          if virsh domstate nas01-backup 2>/dev/null | grep -q running; then
            rm -f "$OVERLAY"
            virsh snapshot-create-as nas01-backup "borg-$(date +%s)" \
              --diskspec vda,file="$OVERLAY" --disk-only --atomic --no-metadata
          fi
        '';
        postHook = ''
          OVERLAY=/var/lib/libvirt/images/nas01-backup.borgsnap.qcow2
          if [ -f "$OVERLAY" ]; then
            virsh blockcommit nas01-backup vda --active --pivot --wait || true
            rm -f "$OVERLAY"
          fi
        '';
      };
      systemd.services."borgbackup-job-system" = {
        after = [ "libvirtd.service" ];
        wants = [ "libvirtd.service" ];
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
