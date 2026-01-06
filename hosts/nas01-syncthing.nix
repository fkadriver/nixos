{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "nas01";

    folders = {
      Documents = {
        path = "/btrfs/raid5/syncthing/Documents";
        devices = [ "latitude" "airbook" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
      Photos = {
        path = "/btrfs/raid5/syncthing/Photos";
        devices = [ "latitude" "airbook" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Downloads = {
        path = "/btrfs/raid5/syncthing/Downloads";
        devices = [ "latitude" "airbook" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
    };
  };
}
