{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      systemPackages = with pkgs; [
        vscodium
        python3Minimal
        claude-code
        shotwell
        xorg.xhost
      ];
    };
    networking = {
      networkmanager = {
        enable = true;
      };
    };
    programs = {
      firefox = {
        enable = true;
      };
      nix-ld.enable = true;
      nix-ld.libraries = with pkgs; [
        # Add common libraries that the binary might need
        stdenv.cc.cc.lib
        zlib
        openssl
  ];
    };
    security = {
      rtkit = {
        enable = true;
      };
    };
    services = {
      pipewire = {
        alsa = {
          enable = true;
          support32Bit = true;
        };
        enable = true;
        pulse = {
          enable = true;
        };
      };
      printing = {
        enable = true;
      };
      xserver = {
        desktopManager = {
          xfce = {
            enable = true;
          };
        };
        displayManager = {
          lightdm = {
            enable = true;
          };
          startx.enable = true;
        };
        enable = true;
      };
    };
  };
}
