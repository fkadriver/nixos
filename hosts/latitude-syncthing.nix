{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "latitude";

    folders = {
      documents = {
        path = "/home/scott/Documents";
        devices = [ "airbook" "server" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };
    };
  };
}
