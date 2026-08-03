{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  # udisks2 is required by fwupd's UEFI capsule plugin to locate the EFI
  # System Partition; without it, fwupd can detect devices but can't stage
  # or install updates.
  services.fwupd.enable = true;
  services.udisks2.enable = true;
}
