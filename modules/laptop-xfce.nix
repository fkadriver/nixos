{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.modules.bitwarden
    inputs.self.modules.wireless
  ];

  config = {
    # Set boot label
    system.nixos.label = "XFCE";

    # Enable X11 and XFCE
    services.xserver = {
      enable = true;
      displayManager.lightdm.enable = true;
      desktopManager.xfce = {
        enable = true;
        enableXfwm = true;
        enableScreensaver = true;
      };

      # Touchpad support for laptops
      libinput = {
        enable = true;
        touchpad = {
          tapping = true;
          naturalScrolling = true;
          disableWhileTyping = true;
        };
      };
    };

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

      # XFCE plugins and utilities
      xfce.xfce4-battery-plugin
      xfce.xfce4-clipman-plugin
      xfce.xfce4-cpugraph-plugin
      xfce.xfce4-datetime-plugin
      xfce.xfce4-netload-plugin
      xfce.xfce4-pulseaudio-plugin
      xfce.xfce4-screenshooter
      xfce.xfce4-systemload-plugin
      xfce.xfce4-taskmanager
      xfce.xfce4-weather-plugin
      xfce.xfce4-whiskermenu-plugin
      xfce.xfce4-xkb-plugin

      # Thunar file manager plugins
      xfce.thunar-archive-plugin
      xfce.thunar-volman
      xfce.thunar-media-tags-plugin

      # Additional XFCE apps
      xfce.ristretto   # Image viewer
      xfce.mousepad    # Text editor
    ];

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
