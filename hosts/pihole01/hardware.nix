{ config, lib, pkgs, nixos-raspberrypi, ... }: {

  # Pi 4B board support comes from nixos-raspberrypi's raspberry-pi-4.base
  # (imported in default.nix): vendor kernel, firmware, config.txt.
  #
  # Generational "kernel" bootloader: every `nixos-rebuild boot` copies the new
  # kernel/initrd/cmdline/DTBs into FIRMWARE/nixos/default *before* the reboot,
  # plus the last `configurationLimit` generations as nixos/<N>-default.
  # (raspberry-pi-nix only did this from a service in the *new* system, so a
  # kernel change deadlocked the boot — 2026-11-17.)
  # Rollback without a boot menu: on the card's FIRMWARE partition, add
  # `os_prefix=nixos/<N>-default/` to config.txt.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Vendor kernel from nixos-raspberrypi's own nixos-26.05 package set (the
  # cached build). Our nixpkgs-unstable modules expect two kernel attributes
  # that 26.05 kernels don't carry yet: `buildDTBs` (hardware.deviceTree
  # default) and `target` (system.boot.loader.kernelFile, read by upstream's
  # bootloader once nixpkgs is >= 26.11). Add them as plain attributes: `//`
  # keeps drvPath/outPath, so this is still exactly the cached kernel. They
  # are re-added after `.override`, which NixOS's kernel.nix always applies
  # (patches/features) and which would otherwise drop them.
  boot.kernelPackages =
    let
      withCompatAttrs = k: k // {
        target = "Image";
        buildDTBs = true;
        override = args: withCompatAttrs (k.override args);
      };
    in
    nixos-raspberrypi.packages.aarch64-linux.linuxPackages_rpi4.extend (self: super: {
      kernel = withCompatAttrs super.kernel;
    });

  # nixos-raspberrypi's base module uses these vendor packages from `pkgs`;
  # our nixpkgs doesn't have them (upstream's own nixosSystem wrapper adds
  # them through an overlay). Take the prebuilt ones from its cached package
  # set, like the kernel, instead of cross-compiling them.
  nixpkgs.overlays = [
    (final: prev: {
      inherit (nixos-raspberrypi.packages.aarch64-linux)
        raspberrypi-utils raspberrypi-udev-rules;
    })
  ];

  # SD card image settings. The nixos-raspberrypi sd-image module sizes
  # FIRMWARE at 1 GiB so it can hold several generations; root ("/",
  # label NIXOS_SD) and /boot/firmware (label FIRMWARE) are defined there.
  sdImage.compressImage = false;

  # Use zram instead of SD swap to protect the card
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
