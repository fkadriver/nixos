{
  description = "Scott's NixOS Configurations";
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
    solaar = {
      url = "github:Svenum/Solaar-Flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    raspberry-pi-nix = {
      url = "github:nix-community/raspberry-pi-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs:
    let
      flakeContext = { inherit inputs; };

      # Auto-discover all modules in ./modules/ (ONLY regular files ending in .nix)
      moduleDir = builtins.readDir ./modules;

      nixModules =
        builtins.filter
          (f: moduleDir.${f} == "regular" && builtins.match ".*\\.nix$" f != null)
          (builtins.attrNames moduleDir);

      mkModuleName = f:
        builtins.substring 0 (builtins.stringLength f - 4) f; # drop ".nix"

      nixosModules = builtins.listToAttrs (map (f: {
        name = mkModuleName f;
        value = import ./modules/${f} flakeContext;
      }) nixModules);

      # Import home-manager configuration for scott
      scottHome = import ./homeConfigurations/scott.nix flakeContext;

    in
    {
      inherit nixosModules;

      # Nix package environments for non-NixOS systems managed by Nix package manager
      packages.x86_64-linux.nas01-env = import ./hosts/nas01/packages.nix { inherit inputs; };

      # Export home-manager configurations
      homeConfigurations = {
        scott = scottHome;
      };

      nixosConfigurations = {
        latitude = import ./hosts/latitude flakeContext;
        latitude-minimal = import ./hosts/latitude/minimal.nix flakeContext;
        latitude-xfce = import ./hosts/latitude/xfce.nix flakeContext;
        prodesk = import ./hosts/prodesk flakeContext;
        vm01 = import ./hosts/vm01 flakeContext;
        pihole01 = import ./hosts/pihole01 flakeContext;
        pihole02 = import ./hosts/pihole02 flakeContext;
        installer = import ./hosts/installer flakeContext;
      };

      # macOS configurations using nix-darwin
      darwinConfigurations = {
        airbook-darwin = import ./hosts/airbook-darwin flakeContext;
      };
    };
}
