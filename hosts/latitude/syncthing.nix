{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "latitude";

    folders = {
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "airbook" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
      Photos = {
        path = "/home/scott/Photos";
        devices = [ "airbook" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Downloads = {
        path = "/home/scott/Downloads";
        devices = [ "airbook" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
    };
  };
}
