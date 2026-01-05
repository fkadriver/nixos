{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
    ];
    config = {
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
