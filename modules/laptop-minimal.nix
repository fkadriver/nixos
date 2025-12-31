{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Minimal laptop applications (XFCE desktop, no Hyprland, no Bitwarden)
    environment.systemPackages = with pkgs; [
      # Development
      vscodium
      python3Minimal
      claude-code

      # Utilities
      unzip
    ];

    # XFCE Desktop Environment
    services.xserver = {
      enable = true;
      desktopManager.xfce.enable = true;
      displayManager.lightdm.enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    # Browser (moved to services for better integration)
    programs.firefox.enable = true;

    # Sound server (PipeWire)
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Printing support
    services.printing.enable = true;

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
