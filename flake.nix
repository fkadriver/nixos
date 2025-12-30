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
        latitude = import ./hosts/latitude.nix flakeContext;
        airbook = import ./hosts/airbook.nix flakeContext;
      };
      modules = {
        bitwarden = import ./modules/bitwarden.nix flakeContext;
        common = import ./modules/common.nix flakeContext;
        hyprland = import ./modules/hyprland.nix flakeContext;
        laptop = import ./modules/laptop.nix flakeContext;
        shell-aliases = import ./modules/shell-aliases.nix flakeContext;
        syncthing = import ./modules/syncthing.nix flakeContext;
        tailscale = import ./modules/tailscale.nix flakeContext;
        user-scott = import ./modules/user-scott.nix flakeContext;
      };
    };
}
