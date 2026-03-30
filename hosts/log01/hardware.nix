# Hardware configuration for Shuttle Zingbox GL014G128W10
# CPU: Intel Celeron (Jasper Lake / similar low-power)
# Storage: 128GB SSD (SATA or eMMC depending on unit)
# Disk partitioning is handled by disko (see disko-config.nix)

{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      # Include modules for both SATA SSD and eMMC variants
      availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" "mmc_block" ];
      kernelModules = [ "dm-snapshot" ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Filesystem configuration is managed by disko-config.nix
  # No manual filesystem or swap configuration needed here

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
