{ device ? "/dev/sda", ... }:
{
  # Disko configuration for nas01 server
  # IMPORTANT: This ONLY partitions the specified device (default: /dev/sda)
  # All other disks (sdb, sdc, sdd, sde, sdf with existing btrfs RAID data) are UNTOUCHED

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = device;
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
            root = {
              size = "100%";
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
  };
}
