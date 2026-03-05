{ inputs, ... }@flakeContext:
{ config, lib, pkgs, modulesPath, ... }: {

  imports = [
    inputs.raspberry-pi-nix.nixosModules.raspberry-pi
    inputs.raspberry-pi-nix.nixosModules.sd-image
  ];

  # Raspberry Pi 3B hardware
  hardware.raspberry-pi."3" = {
    enable = true;
    apply-overlays-dtmerge.enable = true;
  };

  # SD card image settings
  sdImage.compressImage = false;

  # Pi 3B uses its own bootloader — not systemd-boot or grub
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Pi 3B aarch64 kernel
  boot.kernelPackages = pkgs.linuxPackages_rpi3;

  # Basic filesystems (SD card layout managed by raspberry-pi-nix sdImage)
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
