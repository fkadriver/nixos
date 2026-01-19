{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "airbook";

    folders = {
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "latitude" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
      Photos = {
        path = "/home/scott/Photos";
        devices = [ "latitude" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Downloads = {
        path = "/home/scott/Downloads";
        devices = [ "latitude" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
    };
  };
}
