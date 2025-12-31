{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./latitude-hardware.nix
      inputs.self.modules.common
      inputs.self.modules.user-scott
      # Temporarily skip laptop.nix which includes Hyprland and Bitwarden
    ];
    config = {
      # Simple XFCE desktop for testing
      services.xserver = {
        enable = true;
        displayManager.lightdm.enable = true;
        desktopManager.xfce.enable = true;
      };

      # Laptop-specific packages (from laptop.nix but without Hyprland)
      environment.systemPackages = with pkgs; [
        vscodium
        python3Minimal
        claude-code
        firefox
        shotwell
        unzip
      ];

      # WiFi configuration
      networking.networkmanager.ensureProfiles = {
        profiles = {
          JEN_ACRES = {
            connection = {
              id = "JEN_ACRES";
              type = "wifi";
              autoconnect = "true";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "JEN_ACRES";
            };
            wifi-security = {
              key-mgmt = "wpa-psk";
              psk = "goatcheese93";
            };
            ipv4.method = "auto";
            ipv6.method = "auto";
          };
        };
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
