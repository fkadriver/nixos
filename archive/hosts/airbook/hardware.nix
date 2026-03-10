# Hardware configuration for Apple MacBook Air 7,2 (13-inch, Early 2015/Mid 2017)
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # MacBook Air 7,2 specific kernel modules
  # CPU: Intel Core i5-5250U or i7-5650U (Broadwell)
  # NVMe SSD requires nvme module
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "wl" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];

  # Bootloader configuration
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Filesystem configuration is managed by disko
  # These are placeholders for reference:
  # fileSystems."/" = lib.mkDefault {
  #   device = "/dev/disk/by-label/nixos";
  #   fsType = "ext4";
  # };
  #
  # fileSystems."/boot" = lib.mkDefault {
  #   device = "/dev/disk/by-label/boot";
  #   fsType = "vfat";
  # };
  #
  # swapDevices = lib.mkDefault [ ];

  # Broadcom WiFi configuration
  # Blacklist conflicting drivers for broadcom-sta (wl)
  boot.blacklistedKernelModules = [ "b43" "b43legacy" "ssb" "bcm43xx" "brcm80211" "brcmfmac" "brcmsmac" "bcma" ];

  # Enable firmware for Broadcom WiFi
  hardware.enableRedistributableFirmware = true;

  # Allow insecure broadcom-sta package (required for AirBook WiFi)
  # Note: This driver has known CVEs but may be necessary for hardware compatibility
  nixpkgs.config.permittedInsecurePackages = [
    "broadcom-sta-6.30.223.271-59-6.12.60"
  ];

  # Networking configuration
  networking.useDHCP = lib.mkDefault true;
  networking.wireless.enable = lib.mkDefault false; # We'll use NetworkManager instead

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
