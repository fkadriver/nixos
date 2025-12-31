{ inputs, ... }@flakeContext:
{ config, lib, ... }:

{
  # Disko configuration for automated disk partitioning
  # This creates:
  # - 1 GB /boot partition (EFI)
  # - LVM on the rest of the drive with:
  #   - 8 GB swap
  #   - Rest of space for root (/)

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = lib.mkDefault "/dev/sda";  # Override this in host config if needed
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1G";
              type = "EF00";  # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" "umask=0077" ];
              };
            };
            lvm = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "main_vg";
              };
            };
          };
        };
      };
    };

    lvm_vg = {
      main_vg = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "8G";
            content = {
              type = "swap";
              resumeDevice = true;  # Enable hibernation support
            };
          };
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" "noatime" ];
            };
          };
        };
      };
    };
  };
}
