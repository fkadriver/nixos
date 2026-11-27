{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, tsDockerSidecarStart, ... }:
    {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.tsauth
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
      inputs.self.nixosModules.vmware
      inputs.self.nixosModules.pi-builder
      inputs.self.nixosModules.distributed-builds
      inputs.self.nixosModules.deploy-pihole
      inputs.self.nixosModules.screen-recording
      inputs.self.nixosModules.forscan
      inputs.self.nixosModules.esphome-flash
      inputs.self.nixosModules.fwupd
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      services.forscan.enable = true;
      services.esphomeFlash.enable = true;

      # NFS mounts for nas01 shares via Tailscale
      fileSystems."/mnt/nas01/SANS" = {
        device = "nas01.warthog-royal.ts.net:/pool/shares/SANS";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "noauto"
          "nofail"
          "soft"
          "timeo=30"
          "_netdev"
          "x-systemd.requires=tailscaled.service"
          "x-systemd.after=tailscaled.service"
        ];
      };

      fileSystems."/mnt/nas01/photos" = {
        device = "nas01.warthog-royal.ts.net:/pool/shares/photos";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "noauto"
          "nofail"
          "soft"
          "timeo=30"
          "_netdev"
          "x-systemd.requires=tailscaled.service"
          "x-systemd.after=tailscaled.service"
        ];
      };

      # mtga-mcp: local MTGA collection tracker (MTGA runs here via Heroic/Wine)
      home-manager.users.scott = { ... }: {
        home.sessionVariables = {
          MTGA_MCP_PLAYER_LOG = "/home/scott/Games/Heroic/Prefixes/default/Magic The Gathering Arena/drive_c/users/steamuser/AppData/LocalLow/Wizards Of The Coast/MTGA/Player.log";
          MTGA_MCP_RAW_DIR = "/home/scott/Games/Heroic/MagicTheGathering/MTGA_Data/Downloads/Raw";
          MTGA_MCP_DB_PATH = "/home/scott/Documents/mtga-mcp/mtga.db";
        };

        systemd.user.services.mtga-capture = {
          Unit.Description = "MTGA inventory capture";
          Service = {
            Type = "oneshot";
            # Whole assignment must be quoted when the value contains spaces — systemd
            # word-splits unquoted Environment= entries (see systemd.service(5)).
            Environment = [
              "MTGA_MCP_DB_PATH=%h/Documents/mtga-mcp/mtga.db"
              ''"MTGA_MCP_PLAYER_LOG=/home/scott/Games/Heroic/Prefixes/default/Magic The Gathering Arena/drive_c/users/steamuser/AppData/LocalLow/Wizards Of The Coast/MTGA/Player.log"''
              "MTGA_MCP_RAW_DIR=/home/scott/Games/Heroic/MagicTheGathering/MTGA_Data/Downloads/Raw"
            ];
            ExecStart = "/home/scott/git/mtga-mcp/.venv/bin/mtga-mcp capture";
          };
        };

        systemd.user.timers.mtga-capture = {
          Unit.Description = "Run MTGA capture every 15 minutes";
          Timer = {
            OnBootSec = "2min";
            OnUnitActiveSec = "15min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/latitude";
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519_legacy";
      };

      # Allow nixos-rebuild --build-host localhost to build Pi configs locally over SSH loopback.
      # Without this, --target-host delegates the build to the Pi (which lacks sandbox support).
      services.openssh = {
        enable = true;
        listenAddresses = [{ addr = "127.0.0.1"; port = 22; }];
        settings.PasswordAuthentication = false;
      };

      # Root SSH key for --build-host localhost (nixos-rebuild SSHes as root to 127.0.0.1)
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINUZTnLU32N52prAhAMVb8MbqgNe1d5VemjwbWcv4A7l root@latitude"
      ];

      # Tell root's SSH to use the build key when connecting to localhost
      programs.ssh.extraConfig = ''
        Host localhost
          IdentityFile /root/.ssh/id_ed25519_build
          # Key pinned via programs.ssh.knownHosts.localhost (distributed-builds.nix)
          StrictHostKeyChecking yes
      '';

      environment.systemPackages = [
        pkgs.x2goclient  # remote X sessions to OTworkstation
      ];

      # idrive-* client shortcuts (and the xpra client they need) live in
      # modules/daily-driver.nix — they apply to any daily driver, not just this host.

      # xrdp — new X11 KDE session per connection, Tailscale-only
      # xrdp-sesman embeds the startwm.sh path in sesman.ini at build time, so it
      # must be restarted on every rebuild or it keeps running the old session script.
      systemd.services.xrdp-sesman.restartIfChanged = lib.mkForce true;

      services.xrdp = {
        enable = true;
        defaultWindowManager =
          let
            xrdpSession = pkgs.writeShellScript "xrdp-kde-session" ''
              export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
              export XDG_SESSION_TYPE=x11
              export DESKTOP_SESSION=plasma
              export XDG_CURRENT_DESKTOP=KDE

              # Collapse extra XRDP virtual monitors to a single display
              skip_first=false
              for output in $(${pkgs.xrandr}/bin/xrandr --query 2>/dev/null \
                  | ${pkgs.gawk}/bin/awk '/^XRDP/ {print $1}'); do
                if [ "$skip_first" = "false" ]; then
                  skip_first=true
                else
                  ${pkgs.xrandr}/bin/xrandr --output "$output" --off 2>/dev/null || true
                fi
              done

              # plasma-kwin_x11.service is managed by the shared systemd user session.
              # If it's restarting from a previous xrdp session death it will time out
              # (~90s) and SIGTERM our kwin, blanking the desktop. Stop it first.
              ${pkgs.systemd}/bin/systemctl --user stop plasma-kwin_x11.service 2>/dev/null || true

              # startplasma-x11 uses `systemctl --user start` which sees the Wayland
              # session's plasma-plasmashell.service as already active, so plasmashell
              # never starts for the xrdp session.
              # Fix: start kwin_x11 and plasmashell directly inside a private D-Bus
              # session so they don't collide with the Wayland session's registrations.
              ${pkgs.dbus}/bin/dbus-run-session -- sh -c '
                kwin_x11 --replace &
                exec plasmashell
              '

              # Reset service so it can start normally in future Wayland sessions
              ${pkgs.systemd}/bin/systemctl --user reset-failed plasma-kwin_x11.service 2>/dev/null || true
            '';
          in
          "${xrdpSession}";
      };
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 3389 ];

      # Immich Machine Learning Docker Compose stack
      systemd.services.immich-ml-docker = {
        description = "Immich Machine Learning Docker Compose Stack";
        wantedBy = [ "multi-user.target" ];
        after = [ "bitwarden-secrets-sync.service" "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "bitwarden-secrets-sync.service" "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/scott/git/immich_machine_learning";
          ExecStart = tsDockerSidecarStart;
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      system = {
        stateVersion = "25.11";
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
