{
  description = "Scott's NixOS Configurations";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixpkgs-2511.url = "github:NixOS/nixpkgs/nixos-25.11";
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
        latitude-ics = import ./hosts/latitude-ics flakeContext;
        OTworkstation = import ./hosts/OTworkstation flakeContext;
        latitude-minimal = import ./hosts/latitude/minimal.nix flakeContext;
        latitude-xfce = import ./hosts/latitude/xfce.nix flakeContext;
        vm01 = import ./hosts/vm01 flakeContext;
        log01 = import ./hosts/log01 flakeContext;
        pihole01 = import ./hosts/pihole01 flakeContext;
        pihole02 = import ./hosts/pihole02 flakeContext;
        installer = import ./hosts/installer flakeContext;
      };

      # Disko-only configurations used by the installer for disk partitioning.
      # Kept separate from nixosConfigurations so low-RAM hosts (e.g. log01)
      # don't need the disko Rust closure in their installed system.
      diskoConfigurations = {
        # .config gives disko the evaluated attrset it needs (cfg.disko.devices).
        # Passing the raw nixosSystem result fails because it has .config/.options
        # at the top level, not .disko.
        log01 = (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            nixosModules.disko-config
          ];
        }).config;
        OTworkstation = (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            nixosModules.disko-config
          ];
        }).config;
      };

      # macOS configurations using nix-darwin
      darwinConfigurations = {
        airbook-darwin = import ./hosts/airbook-darwin flakeContext;
      };
    };
}
