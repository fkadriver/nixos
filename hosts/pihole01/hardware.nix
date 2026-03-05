{ config, lib, pkgs, ... }: {

  # Pi 4B board selection for raspberry-pi-nix (bcm2711 = Pi 4)
  raspberry-pi-nix.board = "bcm2711";

  # SD card image settings (managed by raspberry-pi-nix sd-image module)
  sdImage.compressImage = false;

  # Root filesystem on SD card
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # Use zram instead of SD swap to protect the card
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
