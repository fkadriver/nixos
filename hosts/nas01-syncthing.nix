{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "server";

    folders = {
      documents = {
        path = "/btrfs/raid5/syncthing/Documents";
        devices = [ "latitude" "airbook" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
    };
  };
}
