{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.vscode-server.nixosModules.default
  ];

  config = {
    # Enable VS Code Server for Remote SSH connections
    services.vscode-server.enable = true;

    # Enable nix-ld for dynamic linking compatibility
    # This is essential for Claude Code and other extensions with native binaries
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Standard C/C++ libraries needed by most native binaries
        stdenv.cc.cc.lib
        zlib

        # Additional libraries that might be needed
        openssl
        curl
        libgit2
        icu
      ];
    };

    # Enable gnome-keyring for secure API key storage
    services.gnome.gnome-keyring.enable = true;

    # PAM integration for keyring auto-unlock
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.sddm.enableGnomeKeyring = true;

    # Install libsecret and other dependencies for Claude Code
    environment.systemPackages = with pkgs; [
      libsecret
      gnome-keyring
      nodejs_22  # Node.js runtime for Claude Code extension
    ];
  };
}
