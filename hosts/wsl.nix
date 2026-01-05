{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.self.nixosModules.common
      inputs.self.nixosModules.user-scott
    ];
    config = {
      # Basic WSL-compatible configuration
      # Note: For full WSL integration, add nixos-wsl as a flake input
      # For now, this is a minimal Linux config that works on WSL

      # Networking
      networking = {
        hostName = "wsl-nixos";
        # Use host's DNS resolution (WSL provides this)
        useHostResolvConf = true;
      };

      # Disable systemd-resolved (conflicts with WSL networking)
      services.resolved.enable = lib.mkForce false;

      # Disable systemd services that don't work well in WSL
      boot.isContainer = true;

      # Minimal WSL-friendly packages
      environment.systemPackages = with pkgs; [
        # Development tools
        vscodium
        python3

        # System utilities
        which
        procps
      ];

      # Use systemd in WSL (supported in WSL2)
      boot.loader.grub.enable = false;

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
