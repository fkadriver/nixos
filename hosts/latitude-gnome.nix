{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.laptop-gnome
      inputs.self.modules.user-scott
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
        nixos.label = "GNOME";
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
