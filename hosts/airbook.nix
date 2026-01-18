{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-hardware.nix
      ./airbook-syncthing.nix
      ./airbook-bluetooth.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.syncthing-declarative
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.wireless
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
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/airbook";
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

      # Filesystem configuration (matches disko partition layout)
      fileSystems."/" = {
        device = "/dev/nvme0n1p3";  # Root is now p3 (after boot and swap)
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/nvme0n1p1";
        fsType = "vfat";
        options = [ "fmask=0077" "dmask=0077" ];
      };

      # Encrypted swap partition with hibernation support
      swapDevices = [{
        device = "/dev/nvme0n1p2";
        randomEncryption.enable = true;  # Encrypt with random key on each boot
      }];

      # Enable hibernation
      boot.resumeDevice = "/dev/nvme0n1p2";

      # Allow unfree and insecure packages needed for Broadcom WiFi
      nixpkgs.config = {
        allowUnfree = true;
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
          "broadcom-sta"
        ];
        permittedInsecurePackages = [
          "broadcom-sta-6.30.223.271-59-6.12.60"
          "broadcom-sta-6.30.223.271-59-6.12.63"
        ];
      };

      networking = {
        hostName = "airbook";
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
