{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
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
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      services.forscan.enable = true;

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
        encryption.passphraseFile = "/etc/borg-passphrase";
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
        # pkgs.rustdesk  # revisit: Wayland screen capture not working
        pkgs.geany
        pkgs.gimp
        pkgs.git-lfs
        # pkgs.input-leap
        pkgs.stable-diffusion-cpp-vulkan
        pkgs.x2goclient  # remote X sessions to OTworkstation
      ];

      # # Input Leap server: allow connections on LAN and via Tailscale
      # # Port 24800 is the default Input Leap/Barrier port
      # networking.firewall.allowedTCPPorts = [ 24800 ];

      # Default text editor for .txt and .conf files
      xdg.mime.defaultApplications = {
        "text/plain" = "geany.desktop";
        "text/x-config" = "geany.desktop";
      };

      # xrdp — new X11 KDE session per connection, Tailscale-only
      services.xrdp = {
        enable = true;
        defaultWindowManager = "startplasma-x11";
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

      # RustDesk service — disabled; Wayland screen capture unsolved
      # systemd.user.services.rustdesk = {
      #   description = "RustDesk Remote Desktop daemon";
      #   wantedBy = [ "graphical-session.target" ];
      #   after = [ "graphical-session.target" ];
      #   serviceConfig = {
      #     ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
      #     Restart = "on-failure";
      #     PassEnvironment = "DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS";
      #     Environment = "XDG_SESSION_TYPE=wayland";
      #   };
      # };

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
