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
  };
  outputs = inputs:
    let
      flakeContext = { inherit inputs; };

      # Auto-discover all modules in ./modules/
      moduleFiles = builtins.attrNames (builtins.readDir ./modules);
      nixModules = builtins.filter (f: builtins.match ".*\\.nix" f != null) moduleFiles;
      mkModuleName = f: builtins.replaceStrings [ ".nix" ] [ "" ] f;
      nixosModules = builtins.listToAttrs (map (f: {
        name = mkModuleName f;
        value = import ./modules/${f} flakeContext;
      }) nixModules);

    in
    {
      inherit nixosModules;

      nixosConfigurations = {
        latitude = import ./hosts/latitude flakeContext;
        latitude-minimal = import ./hosts/latitude/minimal.nix flakeContext;
        latitude-xfce = import ./hosts/latitude/xfce.nix flakeContext;
        airbook = import ./hosts/airbook flakeContext;
        installer = import ./hosts/installer flakeContext;
      };
    };
}
