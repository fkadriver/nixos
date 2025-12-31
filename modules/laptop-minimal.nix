{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Minimal laptop applications (no Hyprland, no Bitwarden)
    environment.systemPackages = with pkgs; [
      # Development
      vscodium
      python3Minimal
      claude-code

      # Browser
      firefox

      # Utilities
      unzip
    ];

    # WiFi configuration for JEN_ACRES
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

    # Dynamic linking support for non-NixOS binaries
    # Required for VSCode extensions with native binaries (like Claude Code)
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

    # Explicitly set nix-ld environment variables system-wide
    # This ensures VSCode and other GUI applications can find them
    environment.sessionVariables = {
      NIX_LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
        stdenv.cc.cc.lib
        zlib
        zstd
        bzip2
        xz
        openssl
        libxcrypt
        libxcrypt-legacy
        curl
        libssh
        util-linux
        systemd
        attr
        acl
        libsodium
        libxml2
        glib
        dbus
      ]);
      NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
    };
  };
}
