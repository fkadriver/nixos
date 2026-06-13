{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "latitude";

    folders = {
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "airbook-darwin" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Downloads = {
        path = "/home/scott/Downloads";
        devices = [ "airbook-darwin" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      tmp = {
        path = "/home/scott/tmp";
        devices = [ "airbook-darwin" ];
      };
    };
  };
}
