{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "airbook";

    # Note: autoAcceptFrom not used here because we use declarative folder config
    # (overrideFolders = true conflicts with autoAcceptFolders)

    folders = {
      # Documents: Full sync with all devices including iPhone
      # iPhone receives via Mobius Sync (one-way configured on iPhone side)
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "latitude" "nas01" "iphone" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      # Photos: Full sync between computers only (no iPhone)
      Photos = {
        path = "/home/scott/Photos";
        devices = [ "latitude" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      # Downloads: Full sync between computers only
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
