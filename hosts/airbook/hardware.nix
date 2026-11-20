# Hardware configuration for Apple MacBook Air 7,2 (13-inch, Early 2015/2017)
# CPU: Intel Core i5-5250U / i7-5650U (Broadwell).
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # The 7,2 SSD is AHCI (SATA-over-PCIe), not NVMe — keep both in the initrd
  # so either reports correctly; dm-snapshot is needed for the LVM root.
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-intel" "wl" ];

  # Layout from disko-config.nix (diskoConfigurations.airbook in flake.nix)
  fileSystems."/" =
    { device = "/dev/mapper/main_vg-root";
      fsType = "ext4";
      options = [ "noatime" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices = [ { device = "/dev/mapper/main_vg-swap"; } ];
  boot.resumeDevice = "/dev/mapper/main_vg-swap";

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Broadcom BCM4360 Wi-Fi: proprietary broadcom-sta (wl). Same setup as the
  # installer ISO (hosts/installer/default.nix). The open drivers conflict.
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.blacklistedKernelModules = [ "b43" "b43legacy" "ssb" "bcm43xx" "brcm80211" "brcmfmac" "brcmsmac" "bcma" ];
  hardware.enableRedistributableFirmware = true;

  # broadcom-sta is unfree and flagged insecure (unmaintained, known CVEs).
  # Derive the exception from the running kernel so kernel bumps don't break
  # eval (the archived config hardcoded per-kernel version strings).
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "broadcom-sta"
  ];
  nixpkgs.config.permittedInsecurePackages = [
    config.boot.kernelPackages.broadcom_sta.name
  ];

  hardware.bluetooth.enable = true;

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
