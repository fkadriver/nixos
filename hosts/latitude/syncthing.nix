{ config, lib, pkgs, ... }: {
  services.syncthing-declarative = {
    enable = true;
    deviceName = "latitude";

    # Latitude is the introducer for nas01 (not managed by NixOS)
    # This allows nas01 to discover other devices through latitude
    introducerFor = [ "nas01" ];

    folders = {
      # Documents: Full sync with all devices including iPhone
      # iPhone receives via Mobius Sync (one-way configured on iPhone side)
      Documents = {
        path = "/home/scott/Documents";
        devices = [ "airbook" "airbook-darwin" "nas01" "iphone" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      # Photos: Full sync between computers only (no iPhone)
      Photos = {
        path = "/home/scott/Photos";
        devices = [ "airbook" "airbook-darwin" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      # Downloads: Full sync between computers only
      Downloads = {
        path = "/home/scott/Downloads";
        devices = [ "airbook" "airbook-darwin" "nas01" ];
        versioning = {
          type = "simple";
          params.keep = "5";
        };
      };
      # tmp: Quick file transfer between mobile devices
      tmp = {
        path = "/home/scott/tmp";
        devices = [ "airbook" "airbook-darwin" "iphone" ];
        # No versioning - temporary files only
      };
    };
  };
}
