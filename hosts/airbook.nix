{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./airbook-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.disko-config
      inputs.self.modules.laptop-xfce
      inputs.self.modules.user-scott
    ];
    config = {
      # Allow unfree and insecure packages needed for Broadcom WiFi
      nixpkgs.config = {
        allowUnfree = true;
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
          "broadcom-sta"
        ];
        permittedInsecurePackages = [
          "broadcom-sta-6.30.223.271-59-6.12.60"
          "broadcom-sta-6.30.223.271-59-6.12.63"
        ];
      };

      networking = {
        hostName = "airbook-nixos";
      };
      system = {
        stateVersion = "25.04";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    inputs.disko.nixosModules.disko
    nixosModule
  ];
  system = "x86_64-linux";
}
