{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      systemPackages = [
        pkgs.vscodium
        pkgs.cmake
        pkgs.python3
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
        };
        enable = true;
      };
    };
  };
}
