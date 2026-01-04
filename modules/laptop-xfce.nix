{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.modules."3d-printing"
    inputs.self.modules.bitwarden
    inputs.self.modules.home-design
    inputs.self.modules.iphone
    inputs.self.modules.vscode
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

    };

    # Touchpad support for laptops
    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    # Laptop-specific applications
    environment.systemPackages = with pkgs; [
      # Development (VSCodium now in vscode module)
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
      xfce4-battery-plugin
      xfce4-clipman-plugin
      xfce4-cpugraph-plugin
      xfce4-netload-plugin
      xfce4-pulseaudio-plugin
      xfce4-screenshooter
      xfce4-systemload-plugin
      xfce4-taskmanager
      xfce4-weather-plugin
      xfce4-whiskermenu-plugin
      xfce4-xkb-plugin

      # Thunar file manager plugins
      thunar-archive-plugin
      thunar-volman
      thunar-media-tags-plugin

      # Additional XFCE apps
      ristretto   # Image viewer
      mousepad    # Text editor
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
