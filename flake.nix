{
  description = "Scott's NixOS Configurations";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixpkgs-2511.url = "github:NixOS/nixpkgs/nixos-25.11";
    # Darwin-specific: nixpkgs-unstable moved to 26.11pre and dropped x86_64-darwin.
    # 26.05 is the last supported branch (through end of 2026) for MacBookAir7,2.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
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
      # Track nix-darwin-26.05 to match nixpkgs-26.05-darwin (branches must line up
      # or the "nix-darwin YY.MM with Nixpkgs YY.MM" assertion aborts activation).
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
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

      # Export home-manager configurations
      homeConfigurations = {
        scott = scottHome;
      };

      nixosConfigurations = {
        latitude = import ./hosts/latitude flakeContext;
        OTworkstation = import ./hosts/OTworkstation flakeContext;
        latitude-minimal = import ./hosts/latitude/minimal.nix flakeContext;
        latitude-xfce = import ./hosts/latitude/xfce.nix flakeContext;
        vm01 = import ./hosts/vm01 flakeContext;
        log01 = import ./hosts/log01 flakeContext;
        nas01 = import ./hosts/nas01 flakeContext;
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
            # 8GB RAM + 2×4GB VMs saturates physical RAM; 32GB swap covers VM overcommit
            ({ lib, ... }: {
              disko.devices.lvm_vg.main_vg.lvs.swap.size = lib.mkForce "32G";
            })
          ];
        }).config;
        # nas01 OS SSD only (Micron, serial UGXVK01J7C9TJA) — pass the by-id
        # device explicitly at install time; ZFS pool and WD drives must not be touched
        nas01 = (inputs.nixpkgs.lib.nixosSystem {
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
