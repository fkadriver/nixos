{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules."3d-printing"
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.home-design
    inputs.self.nixosModules.hyprland
    inputs.self.nixosModules.iphone
    inputs.self.nixosModules.wireless
  ];

  config = {
    # Set boot label
    system.nixos.label = "Hyprland";

    # Laptop-specific applications
    environment.systemPackages = with pkgs; [
      # Development
      # VSCodium with Syncing extension pre-installed for settings/extensions sync
      (vscode-with-extensions.override {
        vscode = vscodium;
        vscodeExtensions = with vscode-extensions; [
          # Syncing extension for settings sync via GitHub Gists
        ] ++ vscode-utils.extensionsFromVscodeMarketplace [
          {
            name = "syncing";
            publisher = "nonoroazoro";
            version = "4.0.1";
            sha256 = "sha256-gZKjLXyb6lyomo/TEqRL90sgs3AcVZeJgC1ZPZm1e08=";
          }
        ];
      })
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
