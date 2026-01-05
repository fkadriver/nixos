{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.self.nixosModules.common
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # WSL-specific configuration
      wsl = {
        enable = true;
        defaultUser = "scott";
        startMenuLaunchers = true;

        # Enable native Docker support
        docker-native.enable = false;  # Use Docker from common.nix instead

        # WSL-specific settings
        wslConf = {
          automount.root = "/mnt";
          network.generateHosts = true;
          network.generateResolvConf = true;
        };
      };

      # Networking
      networking = {
        hostName = "wsl-nixos";
      };

      # Minimal WSL-specific packages
      environment.systemPackages = with pkgs; [
        # WSL utilities
        wslu  # WSL utilities

        # Development tools
        vscodium
        python3

        # Windows interop
        # (wslu provides wslview, wslpath, etc.)
      ];

      system.stateVersion = "25.04";
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
