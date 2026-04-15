{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
      inputs.self.nixosModules.pi-builder
      inputs.self.nixosModules.distributed-builds
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18t_3/borg/repos/latitude";
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

      # RustDesk remote desktop - Tailscale-only access from airbook
      # VMware Workstation for SANS ICS310 RELICS VM (VMware .vmx format)
      # git-lfs for GRFICSv3 OT lab (large Docker image assets)
      environment.systemPackages = [
        pkgs.rustdesk
        pkgs.geany
        pkgs.vmware-workstation
        pkgs.git-lfs
      ];

      # VMware kernel modules required for VMware Workstation
      virtualisation.vmware.host.enable = true;

      # Default text editor for .txt and .conf files
      xdg.mime.defaultApplications = {
        "text/plain" = "geany.desktop";
        "text/x-config" = "geany.desktop";
      };

      # Only allow RustDesk ports on the Tailscale interface
      networking.firewall.interfaces."tailscale0".allowedTCPPortRanges = [
        { from = 21115; to = 21119; }
      ];
      networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 21116 ];

      systemd.user.services.rustdesk = {
        description = "RustDesk Remote Desktop daemon";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
          Restart = "on-failure";
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
