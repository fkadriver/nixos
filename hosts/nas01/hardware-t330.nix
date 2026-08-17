# DRAFT hardware configuration for nas01's Dell PowerEdge T330 replacement.
# NOT wired up yet — hardware.nix (imported by default.nix) still governs the
# live HP ProDesk box. Once the T330 boots the NixOS installer:
#   1. Fill in the TODOs below from real `lsblk`/`ip link`/`nixos-generate-config` output.
#   2. Replace `./hardware.nix` with `./hardware-t330.nix` in default.nix's imports.
#   3. Rename this file to hardware.nix (git mv), retire the old one.
#
# Model: Dell PowerEdge T330 tower, service tag 86B3JH2
# CPU: Xeon E3-1270 v5 (4C/8T, 3.6/4.0GHz turbo, 80W)
# RAM: 16GB 2133MHz ECC UDIMM, 2Rx8 (4 DIMM slots, 3 free for later expansion)
# Storage controller: Dell HBA330 (Adapter, full-height) replacing the stock
#   PERC H730 — true HBA passthrough so ZFS gets raw disk access, no
#   megaraid-passthrough SMART/TRIM quirks. Same PCIe slot/bracket and SAS
#   cabling as the H730 it replaces.
# OS boot disk: TODO — not yet purchased. Confirm whether it lands on the
#   backplane (behind the HBA330, mpt3sas) or a separate onboard SATA/NVMe
#   port before finalizing initrd modules and the fileSystems device below.
# Data storage: existing 3x HGST HDS724040ALE640 4TB (ZFS raidz1 "pool"),
#   reused from the HP ProDesk box. Same physical drives — by-id serials
#   (PK1301PAJ2480X etc.) stay the same, but the by-id *prefix* will very
#   likely change from `ata-HGST_...` to `scsi-...`/`wwn-...` once they're
#   enumerated through the HBA330's mpt3sas driver instead of onboard SATA.
#   Re-verify hd-idle's by-id paths in default.nix against real `ls
#   /dev/disk/by-id/` output — don't assume the old ata- paths still match.
#
# OS disk partitioning is handled by disko (see disko-config.nix) — same
# 1GB boot + LVM (8G swap + root) layout as every other host, unchanged by
# the controller swap.

{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      # TODO verify against `nixos-generate-config --show-hardware-config`
      # once booted. mpt3sas (LSI SAS3008, in-tree) is needed if the boot
      # disk lives behind the HBA330; drop it if the boot disk instead uses
      # a separate onboard SATA/NVMe port not managed by the HBA.
      availableKernelModules = [ "xhci_pci" "ahci" "mpt3sas" "usb_storage" "usbhid" "sd_mod" "nvme" ];
      kernelModules = [ "dm-snapshot" ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    loader = {
      # Dell 13th-gen PowerEdge (T330's generation) supports UEFI boot —
      # confirm BIOS is set to UEFI (not BIOS/Legacy) mode before installing.
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Filesystems — LVM paths are deterministic from disko-config.nix (main_vg),
  # same as every other disko-managed host regardless of which physical disk
  # or controller backs it.
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

  # NICs per Dell's original build sheet (86B3JH2.csv): onboard LOM is
  # Broadcom 5720 dual-port 1GbE (BCM5720, `tg3` driver in-tree), plus a
  # second Broadcom 5720 dual-port 1GbE PCIe card — 4x 1GbE total, not the
  # ProDesk's Intel e1000e. The eno1 e1000e Tx-hang workaround in
  # default.nix's networking.localCommands is HP-specific and should be
  # removed/reassessed once the real interface names are confirmed
  # (`ethtool -i <iface>`) — don't assume the same erratum applies to tg3.
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
