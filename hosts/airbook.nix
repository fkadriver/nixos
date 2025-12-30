{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.laptop
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
    nixosModule
  ];
  system = "x86_64-linux";
}
