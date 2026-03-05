{ inputs, ... }@flakeContext:
{ config, lib, pkgs, modulesPath, ... }: {

  imports = [
    inputs.raspberry-pi-nix.nixosModules.raspberry-pi
    inputs.raspberry-pi-nix.nixosModules.sd-image
  ];

  # Raspberry Pi 4B hardware
  hardware.raspberry-pi."4" = {
    enable = true;
    # Apply all upstream firmware/device tree patches for Pi 4
    apply-overlays-dtmerge.enable = true;
  };

  # SD card image settings
  sdImage.compressImage = false;

  # Pi 4B uses its own bootloader — not systemd-boot or grub
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Pi 4B aarch64 kernel
  boot.kernelPackages = pkgs.linuxPackages_rpi4;

  # Basic filesystems (SD card layout is managed by raspberry-pi-nix sdImage)
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # Hardware-specific: disable zswap, enable swap on SD is hard on the card
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
