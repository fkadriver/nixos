{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.laptop-hyprland
      inputs.self.modules.user-scott
    ];
    config = {
      # Filesystem configuration (not using disko)
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/43055209-fe59-4393-a198-02aded5e5a48";
        fsType = "ext4";
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/55A2-5872";
        fsType = "vfat";
        options = [ "fmask=0077" "dmask=0077" ];
      };
      swapDevices = [
        { device = "/dev/disk/by-uuid/ba0803d5-36af-4d07-98c2-7fc73adab9e9"; }
      ];

      hardware = {
        logitech = {
          wireless = {
            enable = true;
            enableGraphical = true;
          };
        };
      };

      networking = {
        hostName = "latitude-nixos";
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
