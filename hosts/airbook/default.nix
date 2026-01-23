{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      ./bluetooth.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.wireless
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # Filesystem configuration (matches disko partition layout)
      fileSystems."/" = {
        device = "/dev/nvme0n1p3";
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
        randomEncryption.enable = true;
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

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/airbook";
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
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
