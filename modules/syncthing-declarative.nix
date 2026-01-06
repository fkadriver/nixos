{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.syncthing-declarative;

  # Device IDs - these are public identifiers, not secrets
  deviceIds = {
    latitude = "AH7R53Y-PH464V2-R4P7MSY-T7BUWHP-CVPJLL5-ZDIEJZ7-SNDVKDC-3ROY7AZ";
    airbook = "YXQRVDE-2LBYEEB-MRR33Y3-34C3AEM-Q3KV32O-X74BXNC-4BUWSJZ-SOQC3AX";
    nas01 = "O5ICANC-MMANGNF-6S23FIO-UIUK4S2-6E6JKZK-VGNFOJO-BXZ3UBK-DO7JLQ6";
  };

  # Tailscale IP addresses for cross-network connectivity
  tailscaleAddresses = {
    latitude = "100.107.63.92";
    airbook = "100.64.100.37";
    nas01 = "100.116.206.46";
  };
in
{
  options.services.syncthing-declarative = {
    enable = mkEnableOption "Declarative Syncthing configuration";

    deviceName = mkOption {
      type = types.str;
      description = "Name of this device (e.g., 'latitude', 'airbook', 'server')";
    };

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
            devices = [ "latitude" "airbook" ];
          };
          code = {
            path = "/home/scott/Code";
            devices = [ "latitude" "airbook" "server" ];
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
      devices =
        let
          otherDevices = removeAttrs deviceIds [ cfg.deviceName ];
        in
        mapAttrs (name: id: {
          id = id;
          addresses = [ "tcp://${tailscaleAddresses.${name}}:22000" ];
        }) otherDevices;

      # Declarative folder configuration
      overrideFolders = true;
      folders = mapAttrs (name: folderCfg: {
        path = folderCfg.path;
        devices = folderCfg.devices;
        ignorePerms = folderCfg.ignorePerms;
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
