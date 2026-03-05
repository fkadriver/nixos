{ config, lib, pkgs, modulesPath, ... }: {

  imports = [
    # Standard NixOS aarch64 SD image support (provides sdImage + NIXOS_SD label)
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  # SD card image settings
  sdImage.compressImage = false;

  # Root filesystem on SD card (label set by sd-image-aarch64.nix)
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # Pi 3B has only 1GB RAM — use zram to avoid OOM
  zramSwap = {
    enable = true;
    memoryPercent = 75;
  };
}
