{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
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

        # Additional libraries for Claude Code native binary
        glib
        nss
        nspr
        atk
        cups
        libdrm
        gtk3
        pango
        cairo
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        xorg.libxcb
        dbus
        expat
        libxkbcommon
        alsa-lib
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

      # Claude Code CLI from nixpkgs
      claude-code

      # Git is required by Claude Code
      git

      # Additional tools Claude Code uses
      ripgrep  # For code search (rg)
      fd       # For file finding
    ];

  };
}
