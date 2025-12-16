{
  description = "Driver Flake";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    home-manager.url = "flake:home-manager";
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
    in
    {
      homeConfigurations = {
        scott = import ./homeConfigurations/scott.nix flakeContext;
      };
      nixosConfigurations = {
        latitude-nixos = import ./nixosConfigurations/latitude-nixos.nix flakeContext;
      };
      nixosModules = {
        Syncthing = import ./nixosModules/Syncthing.nix flakeContext;
        common = import ./nixosModules/common.nix flakeContext;
        desktop = import ./nixosModules/desktop.nix flakeContext;
        tailscale = import ./nixosModules/tailscale.nix flakeContext;
        user-scott = import ./nixosModules/user-scott.nix flakeContext;
      };
    };
}
