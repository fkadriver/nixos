{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.syncthing-declarative;

  # Device IDs - these are public identifiers, not secrets
  deviceIds = {
    latitude      = "B4FAPKC-JTGMKTY-SE223WL-W2Y3VTT-JHU65E4-X3FUZ2C-4N62X4T-IRI75QZ";
    airbook-darwin = "MIWPTKO-AAFMDLU-BBWGY74-VIR6B2Y-H5OQAV2-COC7RKI-MSS3ZLB-XYBLYQB";
    nas01         = "A7GW6G2-42PAFDM-FULINO3-7DVGMM4-BQY726K-R5BSAV5-MMRGY4I-IYQO7AQ"; # updated 2026-08-22: T330 migration, fresh install regenerated syncthing certs
    iphone        = "SDE4XUA-P5E6GZF-EMPGWPV-POTQWCO-2VJKNC3-T2CQMJ4-4OJQTEU-SSUNDA4";
  };

  # All traffic over Tailscale - no local/global discovery or relays
  deviceAddresses = {
    latitude       = [ "tcp://latitude.warthog-royal.ts.net:22000" ];
    airbook-darwin = [ "tcp://airbook.warthog-royal.ts.net:22000" ];
    nas01          = [ "tcp://nas01.warthog-royal.ts.net:22000" ];
    iphone         = [ "tcp://scott-iphone.warthog-royal.ts.net:22000" ];
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
    # Non-NixOS devices (airbook-darwin via Homebrew, iphone) accept shares manually.

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

    guiUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Username for Syncthing GUI/API basic-auth login. Only gates direct browser access to the web GUI — API-key auth (used by syncthingtray) bypasses it.";
    };

    guiPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a runtime-deployed file (sops-nix or Bitwarden secrets — never
        a literal string) containing the plaintext GUI password. Applied to
        Syncthing's REST API at boot by a oneshot service, so the password
        itself never lands in the Nix store.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.guiPasswordFile != null) -> (cfg.guiUser != null);
        message = "services.syncthing-declarative.guiUser must be set when guiPasswordFile is set";
      }
    ];
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

      # Tailscale-only: disable all discovery and relay mechanisms
      settings.options = {
        globalAnnounceEnabled = false;
        localAnnounceEnabled  = false;
        relaysEnabled         = false;
        natTraversalEnabled   = false;
      };

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

    # Sets GUI basic-auth credentials via the REST API rather than
    # settings.gui.{user,password} — that path would bake the plaintext
    # password into the world-readable Nix store (the update script that
    # applies settings.* embeds the JSON verbatim in a generated unit file).
    systemd.services.syncthing-gui-auth = mkIf (cfg.guiPasswordFile != null) {
      description = "Set Syncthing GUI/API basic-auth credentials";
      after = [ "syncthing.service" "bitwarden-secrets-sync.service" ];
      wants = [ "syncthing.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "scott";
      };
      script = ''
        set -euo pipefail

        API_KEY=""
        for i in $(seq 1 30); do
          API_KEY=$(${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' \
            "${config.services.syncthing.configDir}/config.xml" 2>/dev/null || true)
          [ -n "$API_KEY" ] && break
          sleep 1
        done
        if [ -z "$API_KEY" ]; then
          echo "syncthing-gui-auth: could not read API key from config.xml" >&2
          exit 1
        fi

        PASSWORD=$(cat ${cfg.guiPasswordFile})
        BODY=$(${pkgs.jq}/bin/jq -n --arg user "${cfg.guiUser}" --arg password "$PASSWORD" \
          '{user: $user, password: $password}')

        ${pkgs.curl}/bin/curl -sSf -X PUT -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
          -d "$BODY" "http://127.0.0.1:8384/rest/config/gui" >/dev/null

        if ${pkgs.curl}/bin/curl -sSf -H "X-API-Key: $API_KEY" \
            "http://127.0.0.1:8384/rest/config/restart-required" \
            | ${pkgs.jq}/bin/jq -e .requiresRestart >/dev/null 2>&1; then
          ${pkgs.curl}/bin/curl -sSf -X POST -H "X-API-Key: $API_KEY" \
            "http://127.0.0.1:8384/rest/system/restart" >/dev/null
        fi
      '';
    };
  };
}
