{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-hardware.nix
      ./airbook-syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.syncthing-declarative
      inputs.self.nixosModules.wireless
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # Enable Bitwarden secrets management
      services.bitwarden-secrets = {
        enable = true;
        # secretsFile will default to ../secrets/secrets.yaml
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
        hostName = "airbook-nixos";
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
