{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-nixos-hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.desktop
      inputs.self.nixosModules.user-scott
    ];
    config = {
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
