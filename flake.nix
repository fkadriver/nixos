{
  description = "Driver Flake";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    home-manager.url = "flake:home-manager";
    nixos-hardware.url = "flake:nixos-hardware";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };

      # Custom package overlay for iDrive e360
      overlay = final: prev: {
        idrive-e360 = final.callPackage ./pkgs/idrive-e360 { };
      };
    in
    {
      nixosConfigurations = {
        latitude = import ./hosts/latitude.nix flakeContext;
        latitude-minimal = import ./hosts/latitude-minimal.nix flakeContext;
        airbook = import ./hosts/airbook.nix flakeContext;
        nas01 = import ./hosts/nas01.nix flakeContext;
        installer = import ./hosts/installer.nix flakeContext;
      };
      modules = {
        bitwarden = import ./modules/bitwarden.nix flakeContext;
        common = import ./modules/common.nix flakeContext;
        disko-config = import ./modules/disko-config.nix flakeContext;
        hyprland = import ./modules/hyprland.nix flakeContext;
        idrive-e360 = import ./modules/idrive-e360.nix flakeContext;
        laptop = import ./modules/laptop.nix flakeContext;
        laptop-minimal = import ./modules/laptop-minimal.nix flakeContext;
        shell-aliases = import ./modules/shell-aliases.nix flakeContext;
        syncthing = import ./modules/syncthing.nix flakeContext;
        tailscale = import ./modules/tailscale.nix flakeContext;
        user-scott = import ./modules/user-scott.nix flakeContext;
      };
      overlays.default = overlay;
    };
}
