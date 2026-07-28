# Hardware configuration for nas01
# Model: HP ProDesk 600 G4 DM (TAA), serial MXL9231YDY
# CPU: Intel Core i5-8500T @ 2.10GHz (6c/6t)
# Memory: 8GB DDR4 SODIMM @ 2667 MT/s (1 of 2 slots populated)
# OS storage: Micron MTFDDAK256TBN 256GB SATA SSD (serial UGXVK01J7C9TJA)
# Data storage: 3x HGST 4TB (ZFS raidz1 "pool"), WD 18TB (ext4, borg repos)
# OS disk partitioning is handled by disko (see disko-config.nix)

{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "ahci" "ehci_pci" "usb_storage" "usbhid" "sd_mod" ];
      kernelModules = [ "dm-snapshot" ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Filesystems — LVM paths are deterministic from disko-config.nix (main_vg).
  # Boot partition uses the NIXBOOT FAT label set by disko-config extraArgs.
  fileSystems."/" = {
    device = "/dev/mapper/main_vg-root";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXBOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/mapper/main_vg-swap"; }
  ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
