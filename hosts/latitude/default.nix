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
      # input-leap: KVM server sharing latitude's keyboard/mouse with airbook-darwin
      environment.systemPackages = [
        pkgs.rustdesk
        pkgs.geany
        pkgs.gimp
        pkgs.vmware-workstation
        pkgs.git-lfs
        pkgs.input-leap

        # Switch into the ICS lab configuration (latitude-ics) and back.
        # icsactivate: records the current system generation, then rebuilds to latitude-ics.
        # icsleave:    rolls back to the generation saved by icsactivate (or the previous
        #              generation if the state file is absent), then removes the state file.
        (pkgs.writeShellScriptBin "icsactivate" ''
          set -euo pipefail
          STATE=/var/lib/ics-env/prev-generation

          if [ "$(hostname)" = "latitude-ics" ]; then
            echo "Already in ICS environment (hostname is latitude-ics)."
            exit 0
          fi

          current=$(sudo nix-env --list-generations \
            --profile /nix/var/nix/profiles/system \
            | awk '/\(current\)/{print $1}')

          sudo mkdir -p /var/lib/ics-env
          echo "$current" | sudo tee "$STATE" > /dev/null

          echo "Saved generation $current → $STATE"
          echo "Switching to latitude-ics configuration…"
          cd ~/git/nixos
          sudo nixos-rebuild switch --flake ~/git/nixos#latitude-ics
        '')

        (pkgs.writeShellScriptBin "icsleave" ''
          set -euo pipefail
          STATE=/var/lib/ics-env/prev-generation

          if [ ! -f "$STATE" ]; then
            echo "No saved generation found; rolling back to the previous generation."
            sudo nixos-rebuild switch --rollback
            exit 0
          fi

          target=$(cat "$STATE")
          echo "Rolling back to generation $target…"
          sudo nix-env --switch-generation "$target" \
            --profile /nix/var/nix/profiles/system
          sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
          sudo rm -f "$STATE"
          echo "Returned to generation $target (latitude)."
        '')
      ];

      # Input Leap server: allow connections on LAN and via Tailscale
      # Port 24800 is the default Input Leap/Barrier port
      networking.firewall.allowedTCPPorts = [ 24800 ];

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

      # Input Leap server: share latitude's keyboard/mouse with airbook-darwin
      # Config at ~/.config/InputLeap/input-leap.conf (deployed via home-manager)
      systemd.user.services.input-leap-server = {
        description = "Input Leap keyboard/mouse sharing server";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.input-leap}/bin/input-leaps --no-daemon";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };

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
