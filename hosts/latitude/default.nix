{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.syncthing-declarative
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules."3d-printing"
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # Enable Bitwarden secrets management
      services.bitwarden-secrets = {
        enable = true;
        # secretsFile will default to ../secrets/secrets.yaml

        # Deploy SSH keys from secrets
        sshKeys = {
          id_ed25519 = {
            secretName = "ssh/github_key";
            user = "scott";
          };
          id_ed25519_legacy = {
            secretName = "ssh/legacy_ssh_key";
            user = "scott";
          };
        };
      };

      # Borg backup to NAS via Tailscale
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/latitude";
        paths = [ "/home/scott" ];
        exclude = [
          "/home/scott/.cache"
          "/home/scott/.local/share/Trash"
          "/home/scott/Downloads"
          "/home/scott/.npm"
          "/home/scott/.cargo"
          "/home/scott/.rustup"
          "/home/scott/node_modules"
          "*.pyc"
          "*/__pycache__"
        ];
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
        schedule = "daily";
        prune.keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
      };

      hardware = {
        logitech = {
          wireless = {
            enable = true;
            enableGraphical = true;
          };
        };
      };
      networking = {
        hostName = "latitude";
      };
      system = {
        stateVersion = "25.04";
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
