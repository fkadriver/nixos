{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      ./latitude-syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.bitwarden
    ];
    config = {
      # Enable Bitwarden secrets management
      services.bitwarden-secrets = {
        enable = true;
        # secretsFile will default to ../secrets/secrets.yaml
      };

      hardware = {
        logitech = {
          wireless = {
            enable = true;
            enableGraphical = true;
          };
        };
      };
      networking = {
        hostName = "latitude-nixos";
      };
      system = {
        stateVersion = "25.04";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
