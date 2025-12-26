{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      systemPackages = with pkgs; [
        vscodium
        python3Minimal
        claude-code
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
