{
  description = "Driver Flake";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    home-manager.url = "flake:home-manager";
    nixos-hardware.url = "flake:nixos-hardware";
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
    in
    {
      nixosConfigurations = {
        latitude-nixos = import ./nixosConfigurations/latitude-nixos.nix flakeContext;
      };
      nixosModules = {
        common = import ./nixosModules/common.nix flakeContext;
        desktop = import ./nixosModules/desktop.nix flakeContext;
        latitude-nixos-hardware = import ./nixosModules/latitude-nixos-hardware.nix flakeContext;
        syncthing = import ./nixosModules/syncthing.nix flakeContext;
        tailscale = import ./nixosModules/tailscale.nix flakeContext;
        user-scott = import ./nixosModules/user-scott.nix flakeContext;
      };
    };
}
