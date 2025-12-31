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
    # Required for VSCode extensions with native binaries (like Claude Code)
    # The nix-ld module automatically sets NIX_LD and NIX_LD_LIBRARY_PATH
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Core C/C++ libraries
        stdenv.cc.cc.lib  # libstdc++, libgcc_s

        # Compression libraries
        zlib
        zstd
        bzip2
        xz

        # Crypto and security
        openssl
        libxcrypt
        libxcrypt-legacy

        # Network libraries
        curl
        libssh

        # System libraries
        util-linux
        systemd
        attr
        acl
        libsodium

        # XML/parsing
        libxml2

        # Other common dependencies
        glib
        dbus
      ];
    };
  };
}
