{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "nas01";

    guiUser = "syncthing";
    guiPasswordFile = "/run/bitwarden-secrets/syncthing_gui_password";

    folders = {
      Documents = {
        path = "/pool/syncthing/Documents";
        devices = [ "latitude" "airbook-darwin" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Downloads = {
        path = "/pool/syncthing/Downloads";
        devices = [ "latitude" "airbook-darwin" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      Photos = {
        path = "/pool/syncthing/Photos";
        devices = [ "latitude" "airbook-darwin" "iphone" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
    };
  };
}
