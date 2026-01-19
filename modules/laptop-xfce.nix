{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules."3d-printing"
    # inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.home-design
    inputs.self.nixosModules.iphone
    inputs.self.nixosModules.vscode
    inputs.self.nixosModules.wireless
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
      # Screen saver timeout (15 minutes = 900 seconds)
      serverFlagsSection = ''
        Option "BlankTime" "15"
        Option "StandbyTime" "15"
        Option "SuspendTime" "15"
        Option "OffTime" "15"
      '';
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

    # Bluetooth support
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    services.blueman.enable = true;  # Blueman GUI for XFCE

    # Lid switch behavior - don't suspend when external monitor connected
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    # Laptop-specific applications
    environment.systemPackages = with pkgs; [
      # Development
      python3Minimal
      claude-code

      # Gaming
      heroic
      lutris
      wineWowPackages.stable
      winetricks

      # Media
      shotwell

      # Office
      libreoffice
      thunderbird  # Email client (Gmail + iCloud)

      # Utilities
      unzip
      xarchiver  # Archive manager GUI for Thunar integration
      xdotool    # For mouse button remapping
      xbindkeys  # Bind mouse buttons to keyboard shortcuts
      xorg.xev   # Test mouse button codes

      # XFCE plugins and utilities
      xfce4-battery-plugin
      xfce4-clipman-plugin
      xfce4-cpugraph-plugin
      xfce4-netload-plugin
      xfce4-pulseaudio-plugin
      xfce4-screenshooter
      xfce4-systemload-plugin      # CPU/memory usage for notification area
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
