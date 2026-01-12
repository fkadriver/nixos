{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      # ./latitude-syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.multi-monitor
      # inputs.self.nixosModules.syncthing-declarative
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # Enable Bitwarden secrets management
      # services.bitwarden-secrets = {
      #   enable = true;
      #   # secretsFile will default to ../secrets/secrets.yaml

      #   # Deploy SSH keys from secrets
      #   sshKeys = {
      #     id_ed25519 = {
      #       secretName = "ssh/github_key";
      #       user = "scott";
      #     };
      #     id_ed25519_legacy = {
      #       secretName = "ssh/legacy_ssh_key";
      #       user = "scott";
      #     };
      #   };
      # };

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
