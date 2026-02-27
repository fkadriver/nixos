# Dell Latitude E7270 - Service Tag: 7NYTSF2
# NOTE: This is a placeholder configuration.
# After first boot, regenerate with: nixos-generate-config --show-hardware-config
# Then update the UUIDs below with the actual values from your system.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Dell Latitude E7270 - Intel 6th Gen (Skylake)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Filesystem configuration - PLACEHOLDER UUIDs
  # These will be set by disko during installation
  # If installing manually, update with actual UUIDs from: blkid

  # Disko will handle filesystem configuration
  # If not using disko, uncomment and update the following:
  # fileSystems."/" =
  #   { device = "/dev/disk/by-uuid/PLACEHOLDER-ROOT-UUID";
  #     fsType = "ext4";
  #   };
  #
  # fileSystems."/boot" =
  #   { device = "/dev/disk/by-uuid/PLACEHOLDER-BOOT-UUID";
  #     fsType = "vfat";
  #     options = [ "fmask=0077" "dmask=0077" ];
  #   };
  #
  # swapDevices =
  #   [ { device = "/dev/disk/by-uuid/PLACEHOLDER-SWAP-UUID"; }
  #   ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
