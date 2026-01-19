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
        latitude-xfce = import ./hosts/latitude-xfce.nix flakeContext;
        airbook = import ./hosts/airbook.nix flakeContext;
        installer = import ./hosts/installer.nix flakeContext;
      };
      nixosModules = {
        "3d-printing" = import ./modules/3d-printing.nix flakeContext;
        autorandr-profiles = import ./modules/autorandr-profiles.nix flakeContext;
        bitwarden = import ./modules/bitwarden.nix flakeContext;
        borg-backup = import ./modules/borg-backup.nix flakeContext;
        common = import ./modules/common.nix flakeContext;
        disko-config = import ./modules/disko-config.nix flakeContext;
        home-design = import ./modules/home-design.nix flakeContext;
        idrive-e360 = import ./modules/idrive-e360.nix flakeContext;
        iphone = import ./modules/iphone.nix flakeContext;
        laptop-xfce = import ./modules/laptop-xfce.nix flakeContext;
        laptop-minimal = import ./modules/laptop-minimal.nix flakeContext;
        multi-monitor = import ./modules/multi-monitor.nix flakeContext;
        shell-aliases = import ./modules/shell-aliases.nix flakeContext;
        syncthing = import ./modules/syncthing.nix flakeContext;
        syncthing-declarative = import ./modules/syncthing-declarative.nix flakeContext;
        tailscale = import ./modules/tailscale.nix flakeContext;
        user-scott = import ./modules/user-scott.nix flakeContext;
        vscode = import ./modules/vscode.nix flakeContext;
        wireless = import ./modules/wireless.nix flakeContext;
      };
      overlays.default = overlay;
    };
}
