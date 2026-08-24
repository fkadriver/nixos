{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.bitwarden;

  # Shared helper: start bw serve, run a script via its REST API, then shut it down.
  # bw 2026.x broke cross-process session tokens; the serve API keeps state in one process.
  # Usage: bwServeHelper CLIENT_ID_FILE CLIENT_SECRET_FILE MASTER_PASSWORD_FILE INNER_SCRIPT
  bwServeHelper = pkgs.writeShellScript "bw-serve-helper" ''
    set -euo pipefail

    BW=${pkgs.bitwarden-cli}/bin/bw
    CURL=${pkgs.curl}/bin/curl
    JQ=${pkgs.jq}/bin/jq

    CLIENT_ID_FILE="$1"
    CLIENT_SECRET_FILE="$2"
    MASTER_PASSWORD_FILE="$3"
    INNER_SCRIPT="$4"

    export BW_CLIENTID=$(cat "$CLIENT_ID_FILE")
    export BW_CLIENTSECRET=$(cat "$CLIENT_SECRET_FILE")
    MASTER_PASSWORD=$(cat "$MASTER_PASSWORD_FILE")

    # Login (idempotent — already-logged-in is not an error)
    $BW login --apikey 2>/dev/null || true

    # Find a free port
    BW_PORT=$(${pkgs.python3}/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')

    # Start bw serve in background
    $BW serve --port "$BW_PORT" --hostname 127.0.0.1 &
    BW_PID=$!
    trap "kill $BW_PID 2>/dev/null || true" EXIT

    # Wait for server to be ready (up to 10s)
    for i in $(seq 1 20); do
      if $CURL -sf "http://127.0.0.1:$BW_PORT/status" >/dev/null 2>&1; then
        break
      fi
      sleep 0.5
    done

    # Unlock via REST API
    UNLOCK_RESP=$($CURL -sf -X POST "http://127.0.0.1:$BW_PORT/unlock" \
      -H "Content-Type: application/json" \
      -d "{\"password\":$(echo -n "$MASTER_PASSWORD" | $JQ -Rs .)}" 2>&1)
    UNLOCK_SUCCESS=$(echo "$UNLOCK_RESP" | $JQ -r '.success // false')
    if [ "$UNLOCK_SUCCESS" != "true" ]; then
      echo "Error: Failed to unlock vault: $UNLOCK_RESP" >&2
      exit 1
    fi

    # Sync via REST API
    $CURL -sf -X POST "http://127.0.0.1:$BW_PORT/sync" >/dev/null 2>&1 || true

    # Run the inner script with BW_PORT in the environment
    export BW_PORT
    "$INNER_SCRIPT"
  '';

  # Inner script for the systemd secrets sync service
  syncInnerScript = pkgs.writeShellScript "bw-sync-inner" ''
    set -euo pipefail
    CURL=${pkgs.curl}/bin/curl
    JQ=${pkgs.jq}/bin/jq
    SECRETS_DIR="/run/bitwarden-secrets"

    ${concatMapStringsSep "\n" (secret:
      let
        itemId = secret.itemId;
        field = secret.field;
        name = secret.name;
        mode = secret.mode;
      in ''
        echo "Fetching: ${name} from ${itemId}..."
        ITEM_JSON=$($CURL -sf "http://127.0.0.1:$BW_PORT/object/item/${itemId}" 2>&1)
        DATA=$(echo "$ITEM_JSON" | $JQ -r '.data // empty')
        if [ -z "$DATA" ] || [ "$DATA" = "null" ]; then
          echo "Error: Failed to fetch item ${itemId}: $ITEM_JSON" >&2
          exit 1
        fi
        SECRET_VALUE=$(echo "$DATA" | $JQ -r ${escapeShellArg (
          if field == "password" then "(.login.password // (.fields[]? | select(.name == \"password\") | .value) // empty)"
          else if field == "notes" then ".notes // empty"
          else if field == "username" then ".login.username // empty"
          else "(.fields[]? | select(.name == \"${field}\") | .value) // empty"
          )})
        if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" = "null" ]; then
          echo "Error: Failed to extract field ${field} from ${name}" >&2
          exit 1
        fi
        echo "$SECRET_VALUE" > "$SECRETS_DIR/${name}"
        chmod ${mode} "$SECRETS_DIR/${name}"
        ${optionalString (secret.owner != null) "chown ${secret.owner} \"$SECRETS_DIR/${name}\""}
        echo "  ✓ ${name}"
      ''
    ) (attrValues cfg.secrets)}

    echo "Bitwarden secrets sync completed successfully."
  '';

  # Systemd service to sync secrets from Bitwarden
  syncScript = pkgs.writeShellScript "bw-sync-secrets" ''
    set -euo pipefail

    CLIENT_ID_FILE="${config.sops.secrets."bitwarden/client_id".path}"
    CLIENT_SECRET_FILE="${config.sops.secrets."bitwarden/client_secret".path}"
    MASTER_PASSWORD_FILE="${config.sops.secrets."bitwarden/master_password".path}"
    SECRETS_DIR="/run/bitwarden-secrets"

    if [ ! -f "$CLIENT_ID_FILE" ] || [ ! -f "$CLIENT_SECRET_FILE" ] || [ ! -f "$MASTER_PASSWORD_FILE" ]; then
      echo "Error: Bitwarden credential files not found" >&2
      exit 1
    fi

    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    ${bwServeHelper} "$CLIENT_ID_FILE" "$CLIENT_SECRET_FILE" "$MASTER_PASSWORD_FILE" ${syncInnerScript}
  '';

  # Inner script for the activation script SSH key installation
  sshKeysInnerScript = pkgs.writeShellScript "bw-ssh-keys-inner" ''
    set -euo pipefail
    CURL=${pkgs.curl}/bin/curl
    JQ=${pkgs.jq}/bin/jq

    ${concatMapStringsSep "\n" (name:
      let
        key = cfg.sshKeys.${name};
        userHome = config.users.users.${key.user}.home;
      in ''
        echo "  Fetching SSH key: ${key.keyName} for ${key.user}..."
        SSH_DIR="${userHome}/.ssh"
        KEY_FILE="$SSH_DIR/${key.keyName}"
        mkdir -p "$SSH_DIR"
        chown ${key.user}:users "$SSH_DIR"
        chmod 700 "$SSH_DIR"

        ITEM_JSON=$($CURL -sf "http://127.0.0.1:$BW_PORT/object/item/${key.itemId}" 2>&1)
        KEY_CONTENT=$(echo "$ITEM_JSON" | $JQ -r '.data | (.sshKey.privateKey // .notes // empty)')

        if [ -z "$KEY_CONTENT" ] || [ "$KEY_CONTENT" = "null" ]; then
          echo "    Warning: Failed to fetch SSH key ${key.keyName} from Bitwarden" >&2
        else
          echo "$KEY_CONTENT" > "$KEY_FILE"
          chmod 600 "$KEY_FILE"
          chown ${key.user}:users "$KEY_FILE"
          echo "    ✓ Installed ${key.keyName}"
        fi
      ''
    ) (attrNames cfg.sshKeys)}
  '';

in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  options.services.bitwarden = {
    enable = mkEnableOption "Bitwarden secrets management";

    secretsFile = mkOption {
      type = types.path;
      default = ../secrets/secrets.yaml;
      description = "Path to the encrypted secrets.yaml containing Bitwarden API credentials";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the secret (used as filename in /run/bitwarden-secrets/)";
          };
          itemId = mkOption {
            type = types.str;
            description = "Bitwarden item ID";
          };
          field = mkOption {
            type = types.str;
            default = "password";
            description = "Field to extract: password, notes, username, or custom field name";
          };
          mode = mkOption {
            type = types.str;
            default = "0400";
            description = "File permissions for the secret";
          };
          owner = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Owner of the secret file (e.g., 'user:group')";
          };
        };
      });
      default = {};
      description = "Secrets to fetch from Bitwarden at boot time";
    };

    sshKeys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          user = mkOption {
            type = types.str;
            description = "User to own the SSH key";
          };
          keyName = mkOption {
            type = types.str;
            description = "SSH key filename (e.g., 'id_ed25519')";
          };
          itemId = mkOption {
            type = types.str;
            description = "Bitwarden item ID containing the private key";
          };
        };
      });
      default = {};
      description = "SSH keys to fetch from Bitwarden and install to ~/.ssh/";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ bitwarden-cli jq ];

    sops = {
      defaultSopsFile = cfg.secretsFile;
      age.keyFile = "/var/lib/sops-nix/key.txt";
      secrets."bitwarden/client_id"      = { mode = "0400"; };
      secrets."bitwarden/client_secret"  = { mode = "0400"; };
      secrets."bitwarden/master_password" = { mode = "0400"; };
    };

    systemd.services.bitwarden-secrets-sync = mkIf (cfg.secrets != {}) {
      description = "Sync secrets from Bitwarden";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = syncScript;
        RemainAfterExit = true;
        RuntimeDirectory = "bitwarden-secrets";
        # Execute-only for "other" so non-root consumers named via a secret's
        # `owner` (e.g. syncthing-gui-auth running as scott) can open a file
        # they were individually chown'd/chmod'd for. Traversal doesn't grant
        # listing (no read bit) or access to files still owned root:0400.
        RuntimeDirectoryMode = "0711";
        CacheDirectory = "bitwarden-cli";
        CacheDirectoryMode = "0700";
        Environment = "HOME=/var/cache/bitwarden-cli";
      };

      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 300;
      };
    };

    systemd.timers.bitwarden-secrets-sync = mkIf (cfg.secrets != {}) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Unit = "bitwarden-secrets-sync.service";
      };
    };

    system.activationScripts.bitwarden-ssh-keys = mkIf (cfg.sshKeys != {}) (
      lib.stringAfter [ "users" "setupSecrets" ] ''
        echo "Installing SSH keys from Bitwarden..."

        CLIENT_ID_FILE="${config.sops.secrets."bitwarden/client_id".path}"
        CLIENT_SECRET_FILE="${config.sops.secrets."bitwarden/client_secret".path}"
        MASTER_PASSWORD_FILE="${config.sops.secrets."bitwarden/master_password".path}"

        if [ ! -f "$CLIENT_ID_FILE" ] || [ ! -f "$CLIENT_SECRET_FILE" ] || [ ! -f "$MASTER_PASSWORD_FILE" ]; then
          echo "Warning: Bitwarden credential files not found, skipping SSH key installation" >&2
        else
          export HOME=/var/cache/bitwarden-cli
          mkdir -p "$HOME"
          ${bwServeHelper} "$CLIENT_ID_FILE" "$CLIENT_SECRET_FILE" "$MASTER_PASSWORD_FILE" ${sshKeysInnerScript}
        fi
      ''
    );

    system.activationScripts.sops-nix-setup = lib.mkBefore ''
      if [ ! -f /var/lib/sops-nix/key.txt ]; then
        mkdir -p /var/lib/sops-nix
        ${pkgs.age}/bin/age-keygen -o /var/lib/sops-nix/key.txt
        chmod 600 /var/lib/sops-nix/key.txt
        echo "Generated new age key for sops-nix at /var/lib/sops-nix/key.txt"
        echo "Public key: $(${pkgs.age}/bin/age-keygen -y /var/lib/sops-nix/key.txt)"
      fi
    '';
  };
}
