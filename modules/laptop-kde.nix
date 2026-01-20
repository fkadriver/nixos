{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules."3d-printing"
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.home-design
    inputs.self.nixosModules.iphone
    inputs.self.nixosModules.syncthing-declarative
    inputs.self.nixosModules.vscode
    inputs.self.nixosModules.wireless
  ];

  config = {
    # Set boot label
    system.nixos.label = "KDE";

    # Enable Bitwarden secrets management
    services.bitwarden-secrets = {
      enable = true;
      sshKeys = {
        id_ed25519 = {
          secretName = "ssh/github_key";
          user = "scott";
        };
        id_ed25519_legacy = {
          secretName = "ssh/legacy_ssh_key";
          user = "scott";
        };
      };
    };

    # Enable KDE Plasma
    services.xserver.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;

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
      kdePackages.gwenview        # KDE image viewer

      # Office
      libreoffice
      thunderbird

      # Utilities
      unzip
      kdePackages.ark             # KDE archive manager
      kdePackages.kcalc           # KDE calculator
      kdePackages.spectacle       # KDE screenshot tool

      # KDE utilities
      kdePackages.dolphin          # File manager
      kdePackages.konsole          # Terminal
      kdePackages.kate             # Text editor
      kdePackages.kcmutils         # KDE system settings modules
      kdePackages.kscreen          # Multi-monitor management
      kdePackages.plasma-systemmonitor  # System monitor
      kdePackages.kinfocenter      # System information
      kdePackages.plasma-nm        # Network manager applet
      kdePackages.plasma-pa        # PulseAudio/PipeWire applet
      kdePackages.bluedevil        # Bluetooth manager
      kdePackages.powerdevil       # Power management
      kdePackages.kgamma           # Monitor gamma control

      # Windows 11 theming (optional - can install via System Settings)
      # kdePackages.breeze          # Default theme (already included)
    ];

    # Browser
    programs.firefox.enable = true;

    # KDE Connect for phone integration
    programs.kdeconnect.enable = true;

    # Dynamic linking support for non-NixOS binaries
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Core C/C++ libraries
        stdenv.cc.cc.lib

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

    # PipeWire for audio (KDE integrates well with PipeWire)
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Disable power-profiles-daemon to avoid conflict with TLP (from multi-monitor module)
    services.power-profiles-daemon.enable = false;
  };
}
