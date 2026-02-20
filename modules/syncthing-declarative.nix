{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.syncthing-declarative;

  # Device IDs - these are public identifiers, not secrets
  deviceIds = {
    latitude = "B4FAPKC-JTGMKTY-SE223WL-W2Y3VTT-JHU65E4-X3FUZ2C-4N62X4T-IRI75QZ";
    airbook = "YWSK64M-74SMQZM-AX7M4DN-4CV3IZB-K5NZSXV-KUUPX7X-UONQQLM-Y3BEMQW";
    nas01 = "O5ICANC-MMANGNF-6S23FIO-UIUK4S2-6E6JKZK-VGNFOJO-BXZ3UBK-DO7JLQ6";
    iphone = "SDE4XUA-P5E6GZF-EMPGWPV-POTQWCO-2VJKNC3-T2CQMJ4-4OJQTEU-SSUNDA4";
  };

  # All devices are always behind Tailscale
  deviceAddresses = {
    latitude = [ "tcp://latitude.warthog-royal.ts.net:22000" ];
    airbook = [ "tcp://airbook.warthog-royal.ts.net:22000" ];
    nas01 = [ "tcp://nas01.warthog-royal.ts.net:22000" ];  # Always use Tailscale for nas01
    iphone = [ "tcp://scott-iphone.warthog-royal.ts.net:22000" ];
  };
in
{
  options.services.syncthing-declarative = {
    enable = mkEnableOption "Declarative Syncthing configuration";

    deviceName = mkOption {
      type = types.str;
      description = "Name of this device (e.g., 'latitude', 'airbook', 'server')";
    };

    # Devices that this host acts as introducer for
    introducerFor = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of device names this host is an introducer for";
      example = [ "nas01" ];
    };

    # Note: autoAcceptFolders is NOT supported when using declarative folder config
    # (overrideFolders = true), as auto-accepted folders would be deleted on rebuild.
    # Configure auto-accept on non-NixOS devices like nas01 instead.

    folders = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Path to the folder";
          };
          devices = mkOption {
            type = types.listOf types.str;
            description = "List of device names to share with";
          };
          ignorePerms = mkOption {
            type = types.bool;
            default = false;
            description = "Ignore permissions on this folder";
          };
          type = mkOption {
            type = types.enum [ "sendreceive" "sendonly" "receiveonly" ];
            default = "sendreceive";
            description = "Folder sync type: sendreceive (default), sendonly, or receiveonly";
          };
          versioning = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                type = mkOption {
                  type = types.enum [ "simple" "trashcan" "staggered" "external" ];
                  default = "simple";
                };
                params = mkOption {
                  type = types.attrsOf types.str;
                  default = {};
                };
              };
            });
            default = null;
            description = "Versioning configuration";
          };
        };
      });
      default = {};
      description = "Folders to sync";
      example = literalExpression ''
        {
          documents = {
            path = "/home/scott/Documents";
            devices = [ "latitude" "airbook" "iphone" ];
            type = "sendonly";  # One-way sync to other devices
          };
          code = {
            path = "/home/scott/Code";
            devices = [ "latitude" "airbook" "server" ];
            type = "sendreceive";  # Full bidirectional sync (default)
            versioning = {
              type = "simple";
              params.keep = "5";
            };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Basic Syncthing service
    services.syncthing = {
      enable = true;
      user = "scott";
      dataDir = "/home/scott";
      configDir = "/home/scott/.config/syncthing";

      # Web UI settings
      guiAddress = "127.0.0.1:8384";

      # Declarative device configuration
      overrideDevices = true;
      settings.devices =
        let
          otherDevices = removeAttrs deviceIds [ cfg.deviceName ];
        in
        mapAttrs (name: id: {
          id = id;
          addresses = deviceAddresses.${name};
          # Mark this host as introducer for certain devices
          introducer = elem name cfg.introducerFor;
          # Note: autoAcceptFolders is incompatible with overrideFolders=true
        }) otherDevices;

      # Declarative folder configuration
      overrideFolders = true;
      settings.folders = mapAttrs (name: folderCfg: {
        path = folderCfg.path;
        devices = folderCfg.devices;
        ignorePerms = folderCfg.ignorePerms;
        type = folderCfg.type;
        versioning = folderCfg.versioning;
      }) cfg.folders;
    };

    # Open firewall for Syncthing
    networking.firewall = {
      allowedTCPPorts = [ 22000 ];  # Syncthing transfer
      allowedUDPPorts = [ 22000 21027 ];  # Syncthing transfer + discovery
    };

    # Ensure syncthing user can access home directory
    systemd.services.syncthing.serviceConfig = {
      UMask = "0077";
    };
  };
}
