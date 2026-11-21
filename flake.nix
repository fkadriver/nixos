{
  description = "Scott's NixOS Configurations";
  inputs = {
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    # nixos-unstable only advances once Hydra's full NixOS build+test matrix
    # passes, so whatever revision it's on is already near-fully cached —
    # used for desktop/app packages that don't need to be bleeding-edge.
    # Base nixpkgs (above) stays on the faster-moving nixpkgs-unstable branch
    # for common.nix and security-relevant modules (kernel, tailscale, borg,
    # bitwarden) where freshness matters more than cache-hit rate.
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Darwin-specific: nixpkgs-unstable moved to 26.11pre and dropped x86_64-darwin.
    # 26.05 is the last supported branch (through end of 2026) for MacBookAir7,2.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    home-manager = {
      url = "flake:home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "flake:nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # No nixpkgs follows: this flake has no nixpkgs input of its own (only
    # flake-parts), so a follows here just produces an eval warning.
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    # pihole01 (Pi 4B) kernel, firmware and bootloader. Deliberately NO
    # nixpkgs follows: the vendor kernel is built from this flake's own pinned
    # nixpkgs, and that exact build is what nixos-raspberrypi.cachix.org
    # serves. Following our nixpkgs changes the kernel hash, which means a
    # 1-2 day qemu-emulated kernel build again (what raspberry-pi-nix did).
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/develop";
    tether = {
      url = "github:zackb/tether";
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

      # Stage-1 bootstrap systems for the staged install (modules/bootstrap.nix,
      # docs/installing.md): the host's own hardware.nix + bootstrap.nix, with
      # the same hostName and stateVersion as its full config. Piholes are
      # excluded (SD images via scripts/deploy-piholes.sh, not the installer).
      bootstrapHardware = {
        airbook = ./hosts/airbook/hardware.nix;
        latitude = ./hosts/latitude/hardware.nix;
        OTworkstation = ./hosts/OTworkstation/hardware.nix;
        vm01 = ./hosts/vm01/hardware-configuration.nix;
        nas01 = ./hosts/nas01/hardware.nix;
        log01 = ./hosts/log01/hardware.nix;
      };
      mkBootstrap = name: hardware: inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          hardware
          nixosModules.bootstrap
          {
            networking.hostName = name;
            system.stateVersion =
              inputs.self.nixosConfigurations.${name}.config.system.stateVersion;
          }
        ];
      };
      bootstrapConfigurations = inputs.nixpkgs.lib.mapAttrs'
        (name: hw: inputs.nixpkgs.lib.nameValuePair "${name}-bootstrap" (mkBootstrap name hw))
        bootstrapHardware;

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
        airbook = import ./hosts/airbook flakeContext;
        vm01 = import ./hosts/vm01 flakeContext;
        log01 = import ./hosts/log01 flakeContext;
        nas01 = import ./hosts/nas01 flakeContext;
        pihole01 = import ./hosts/pihole01 flakeContext;
        pihole02 = import ./hosts/pihole02 flakeContext;
        installer = import ./hosts/installer flakeContext;
      } // bootstrapConfigurations;

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
        # MacBook Air 7,2 internal SSD: /dev/nvme0n1 (/dev/sda is the SD card reader).
        # Set here so a plain `disko --flake ...#airbook` targets the right
        # disk; the installer also overrides it with the device you pick.
        airbook = (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            nixosModules.disko-config
            ({ lib, ... }: {
              disko.devices.disk.main.device = lib.mkForce "/dev/nvme0n1";
            })
          ];
        }).config;
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
