{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.tsauth
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
      inputs.self.nixosModules.vmware
      inputs.self.nixosModules.pi-builder
      inputs.self.nixosModules.distributed-builds
      inputs.self.nixosModules.screen-recording
      inputs.self.nixosModules.forscan
      inputs.self.nixosModules.mcp-nixos
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      services.forscan.enable = true;
      programs.mcp-nixos.enable = true;

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

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
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
          StrictHostKeyChecking no
      '';

      # VMware Workstation for SANS ICS310 RELICS VM (VMware .vmx format)
      # git-lfs for GRFICSv3 OT lab (large Docker image assets)
      environment.systemPackages = [
        pkgs.anki
        pkgs.geany
        pkgs.gimp
        pkgs.git-lfs
        # pkgs.input-leap
        pkgs.stable-diffusion-cpp-vulkan
        pkgs.syncthingtray
        pkgs.x2goclient  # remote X sessions to OTworkstation
      ];

      sops.secrets."syncthing_nas01_apikey" = {
        owner = "scott";
      };

      systemd.user.services.syncthingtray = {
        description = "Syncthing Tray";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStartPre = pkgs.writeShellScript "syncthingtray-configure" ''
            LOCAL_KEY=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<apikey>)[^<]+' \
              "$HOME/.config/syncthing/config.xml")
            NAS01_KEY=$(cat /run/secrets/syncthing_nas01_apikey)

            ${pkgs.python3}/bin/python3 - "$LOCAL_KEY" "$NAS01_KEY" <<'PYEOF'
import configparser, sys, os
local_key, nas01_key = sys.argv[1], sys.argv[2]
path = os.path.join(os.environ['HOME'], '.config', 'syncthingtray.ini')
config = configparser.RawConfigParser()
config.optionxform = str
if os.path.exists(path):
    config.read(path)
if not config.has_section('tray'):
    config.add_section('tray')
for key, val in [
    (r'connections\1\apiKey',       f'@ByteArray({local_key})'),
    (r'connections\1\syncthingUrl', 'http://localhost:8384'),
    (r'connections\1\autoConnect',  'true'),
    (r'connections\1\label',        'latitude'),
    (r'connections\2\apiKey',       f'@ByteArray({nas01_key})'),
    (r'connections\2\syncthingUrl', 'http://nas01.warthog-royal.ts.net:8384'),
    (r'connections\2\autoConnect',  'true'),
    (r'connections\2\label',        'nas01'),
    (r'connections\size',           '2'),
]:
    config.set('tray', key, val)
with open(path, 'w') as f:
    config.write(f, space_around_delimiters=False)
PYEOF
          '';
          ExecStart = "${pkgs.syncthingtray}/bin/syncthingtray --wait";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };

      # # Input Leap server: allow connections on LAN and via Tailscale
      # # Port 24800 is the default Input Leap/Barrier port
      # networking.firewall.allowedTCPPorts = [ 24800 ];

      # Default text editor for .txt and .conf files
      xdg.mime.defaultApplications = {
        "text/plain" = "geany.desktop";
        "text/x-config" = "geany.desktop";
      };

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

      # # Input Leap server: share latitude's keyboard/mouse with airbook-darwin
      # # Config at ~/.config/InputLeap/input-leap.conf (deployed via home-manager)
      # systemd.user.services.input-leap-server = {
      #   description = "Input Leap keyboard/mouse sharing server";
      #   wantedBy = [ "graphical-session.target" ];
      #   after = [ "graphical-session.target" "network.target" ];
      #   serviceConfig = {
      #     ExecStart = "${pkgs.input-leap}/bin/input-leaps --no-daemon";
      #     Restart = "on-failure";
      #     RestartSec = 3;
      #   };
      # };

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
          ExecStart = pkgs.writeShellScript "immich-ml-docker-start" ''
            set -euo pipefail
            export TS_AUTHKEY=$(cat /run/bitwarden-secrets/container_ts_authkey)
            exec ${pkgs.docker}/bin/docker compose up -d
          '';
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
