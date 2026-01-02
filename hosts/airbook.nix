{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.disko-config
      inputs.self.modules.laptop-xfce
      inputs.self.modules.user-scott
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
    inputs.disko.nixosModules.disko
    nixosModule
  ];
  system = "x86_64-linux";
}
