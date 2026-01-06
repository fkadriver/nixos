{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # nas01 hardware configuration
  # Intel i3-2120 CPU @ 3.30GHz
  # 16GB OS drive (sda) + btrfs RAID arrays

  boot = {
    initrd = {
      availableKernelModules = [ "ehci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
      kernelModules = [ ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    # Bootloader configuration
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Enable btrfs support for RAID arrays
    supportedFilesystems = [ "btrfs" ];
  };

  # Disko handles OS disk (sda) partitioning
  # RAID arrays (sdb, sdd, sdf, etc.) configured separately

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
