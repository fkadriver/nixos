{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "airbook";

    folders = {
      documents = {
        path = "/home/scott/Documents";
        devices = [ "latitude" "server" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
    };
  };
}
