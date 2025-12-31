{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.laptop
      inputs.self.modules.user-scott
    ];
    config = {
      # Explicitly disable XFCE and LightDM
      services.xserver.enable = lib.mkForce false;
      services.xserver.displayManager.lightdm.enable = lib.mkForce false;
      services.xserver.desktopManager.xfce.enable = lib.mkForce false;

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
