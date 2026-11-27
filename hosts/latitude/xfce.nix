{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.autorandr-profiles
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.fwupd
    ];
    config = {
      # Filesystems come from ./hardware.nix (its diskoLayout switch).

      networking = {
        hostName = "latitude";
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
