{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.syncthing
      inputs.self.nixosModules.laptop-minimal
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
      inputs.self.nixosModules.vmware
    ];
    config = {
      networking.hostName = "OTworkstation";

      system.stateVersion = "25.11";
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
