{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      systemPackages = with pkgs; [
        vscodium
        python3Minimal
        claude-code
        heroic
        lutris
        shotwell
        unzip
        wineWowPackages.stable
        winetricks
        xorg.xhost
      ];
    };
    networking = {
      networkmanager = {
        enable = true;
        ensureProfiles = {
          profiles = {
            JEN_ACRES = {
              connection = {
                id = "JEN_ACRES";
                type = "wifi";
                autoconnect = "true";
              };
              wifi = {
                mode = "infrastructure";
                ssid = "JEN_ACRES";
              };
              wifi-security = {
                key-mgmt = "wpa-psk";
                psk = "goatcheese93";
              };
              ipv4 = {
                method = "auto";
              };
              ipv6 = {
                method = "auto";
              };
            };
          };
        };
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
