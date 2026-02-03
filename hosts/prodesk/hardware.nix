# Hardware configuration for HP ProDesk 600 G4 DM PC
# CPU: Intel Core i5-8500T (Coffee Lake, 6 cores, 9MB cache)
# GPU: Intel UHD Graphics 630 (integrated)
# This is a template - run `nixos-generate-config` on the actual hardware
# and replace this file with the generated hardware-configuration.nix

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration
  boot = {
    initrd = {
      availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
      kernelModules = [ ];
    };
    kernelModules = [ "kvm-intel" ];  # Intel Core i5-8500T (Coffee Lake)
    extraModulePackages = [ ];

    # Use systemd-boot for UEFI systems
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Filesystem configuration
  # IMPORTANT: Replace these with your actual disk UUIDs after installation
  # Get UUIDs with: blkid
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap configuration (optional)
  # swapDevices = [
  #   { device = "/dev/disk/by-uuid/REPLACE-WITH-SWAP-UUID"; }
  # ];

  # CPU microcode updates for Intel Coffee Lake
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Enable all firmware (including proprietary)
  hardware.enableRedistributableFirmware = true;

  # Intel UHD Graphics 630 support
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver  # LIBVA_DRIVER_NAME=i965 (older but works better for some)
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Networking
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
