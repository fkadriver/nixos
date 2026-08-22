# Hardware configuration for nas01's Dell PowerEdge T330.
# Live since 2026-08-20 (NixOS installed, UEFI boot). Kernel modules below
# are taken verbatim from `nixos-generate-config --show-hardware-config`
# run on the live box (2026-08-22) — not guessed.
#
# Model: Dell PowerEdge T330 tower, service tag 86B3JH2
# CPU: Xeon E3-1270 v5 (4C/8T, 3.6/4.0GHz turbo, 80W)
# RAM: 16GB 2133MHz ECC UDIMM, 2Rx8 (4 DIMM slots, 3 free for later expansion)
# Storage controller: Dell HBA330 (Adapter, full-height) replacing the stock
#   PERC H730 — true HBA passthrough so ZFS gets raw disk access, no
#   megaraid-passthrough SMART/TRIM quirks. Same PCIe slot/bracket and SAS
#   cabling as the H730 it replaces.
# OS boot disk: 500GB SATA HDD, confirmed behind the HBA330 backplane —
#   `mpt3sas` is required in initrd (confirmed via nixos-generate-config,
#   not assumed).
# Data storage: existing 3x HGST HDS724040ALE640 4TB (ZFS raidz1 "pool"),
#   reused from the HP ProDesk box. Same physical drives, same by-id
#   serials (PK1301PAJ2480X etc.) — confirmed 2026-08-22 the by-id *prefix*
#   stayed `ata-HGST_...` even behind the HBA330's mpt3sas driver (the
#   anticipated shift to `scsi-.../wwn-...` did not happen), so hd-idle's
#   paths in default.nix needed no changes.
#
# OS disk partitioning is handled by disko (see disko-config.nix) — same
# 1GB boot + LVM (8G swap + root) layout as every other host, unchanged by
# the controller swap.
# OS-disk mirroring was considered (mdadm, spare 1TB drive) and declined —
# single disk, spare kept cold. See docs/nas01.md.

{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      # From nixos-generate-config --show-hardware-config, 2026-08-22.
      # mpt3sas (LSI SAS3008, in-tree) confirmed required — the boot disk
      # is behind the HBA330 backplane.
      availableKernelModules = [ "xhci_pci" "ahci" "mpt3sas" "usbhid" "sd_mod" "sr_mod" ];
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
  # Broadcom BCM5720 dual-port 1GbE, plus a second BCM5720 dual-port 1GbE
  # PCIe card — 4x 1GbE total per the build sheet. Confirmed 2026-08-22 via
  # `ethtool -i eno1`: driver `tg3`, firmware 21.60.2 — matches the flashed
  # NIC firmware in the update log. Only eno1 (up) and eno2 (down, no cable)
  # show in `ip link` — the second PCIe card doesn't currently enumerate;
  # unconfirmed whether it's not installed or just not cabled. The ProDesk's
  # Intel e1000e Tx-hang workaround (EEE/TSO/GSO/GRO off) has been removed
  # from default.nix's networking.localCommands — wrong NIC/driver entirely,
  # and tg3 hasn't shown any hang symptoms so no replacement mitigation was
  # added speculatively.
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
