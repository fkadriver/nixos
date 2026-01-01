{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    # inputs.self.modules.bitwarden
    inputs.self.modules.wireless
  ];

  config = {
    # Set boot label
    system.nixos.label = "GNOME";

    # Enable X11 and GNOME
    services.xserver.enable = true;
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Exclude some default GNOME applications to keep it cleaner
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany  # GNOME web browser (we use Firefox)
      geary     # Email client
    ];

    # Fix cursor theme (prevents square cursor issue)
    environment.variables = {
      XCURSOR_THEME = "Adwaita";
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

      # GNOME-specific utilities
      gnome-tweaks
      gnomeExtensions.appindicator
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
