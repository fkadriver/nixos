{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    # Reuses the "airbook-darwin" device name so latitude/nas01 folder lists
    # need no changes; only one OS runs on this hardware at a time. The macOS
    # certs couldn't be recovered (FileVault), so the NixOS install has its
    # own ID — deviceIds.airbook-darwin in modules/syncthing-declarative.nix
    # was updated to it. Reinstalling either OS means updating that ID again.
    deviceName = "airbook-darwin";

    folders = {
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "latitude" "nas01" "iphone" ];
        versioning = {
          type = "simple";
          params.keep = "5";
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
      # tmp: quick transfer between personal devices (no nas01)
      tmp = {
        path = "/home/scott/tmp";
        devices = [ "latitude" "iphone" ];
      };
    };
  };
}
