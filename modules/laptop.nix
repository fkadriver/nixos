{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.modules.hyprland
    inputs.self.modules.bitwarden
  ];

  config = {
    # Laptop-specific applications
    environment.systemPackages = with pkgs; [
      # Development
      vscodium
      python3Minimal
      claude-code

      # Gaming
      heroic
      lutris
      wineWowPackages.stable
      winetricks

      # Media
      shotwell

      # Utilities
      unzip
    ];

    # WiFi configuration for JEN_ACRES
    # This needs to stay here to allow network access for bitwarden and other services
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
          ipv4 = {
            method = "auto";
          };
          ipv6 = {
            method = "auto";
          };
        };
      };
    };

    # Browser
    programs.firefox.enable = true;

    # Dynamic linking support for non-NixOS binaries
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
      ];
    };
  };
}
