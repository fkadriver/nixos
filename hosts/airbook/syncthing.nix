{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    # Deliberately the same Syncthing identity as macOS (airbook-darwin): only
    # one OS runs on this hardware at a time, and reusing it means latitude
    # and nas01 need no changes. Requires copying cert.pem + key.pem from
    # macOS (~/Library/Application Support/Syncthing/) into
    # ~/.config/syncthing/ BEFORE syncthing first starts here — otherwise a
    # fresh device ID is generated and deviceIds.airbook-darwin in
    # modules/syncthing-declarative.nix must be updated to match.
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
