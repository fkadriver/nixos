{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.bitwarden;

  # Helper script to fetch a secret from Bitwarden
  # Expects BW_SESSION to be already set in environment
  fetchItemField = pkgs.writeShellScript "bw-fetch-field" ''
    set -euo pipefail

    ITEM_ID="$1"
    FIELD="$2"  # "password", "notes", or "username"

    # Fetch the item and extract the field
    case "$FIELD" in
      password)
        ${pkgs.bitwarden-cli}/bin/bw get item "$ITEM_ID" | ${pkgs.jq}/bin/jq -r '.login.password // empty'
        ;;
      notes)
        ${pkgs.bitwarden-cli}/bin/bw get item "$ITEM_ID" | ${pkgs.jq}/bin/jq -r '.notes // empty'
        ;;
      username)
        ${pkgs.bitwarden-cli}/bin/bw get item "$ITEM_ID" | ${pkgs.jq}/bin/jq -r '.login.username // empty'
        ;;
      *)
        echo "Error: Unknown field type: $FIELD" >&2
        exit 1
        ;;
    esac
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

    export BW_CLIENTID=$(cat "$CLIENT_ID_FILE")
    export BW_CLIENTSECRET=$(cat "$CLIENT_SECRET_FILE")
    export BW_PASSWORD=$(cat "$MASTER_PASSWORD_FILE")

    # Ensure secrets directory exists
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    # Login with API key
    echo "Authenticating to Bitwarden..."
    ${pkgs.bitwarden-cli}/bin/bw login --apikey --quiet 2>/dev/null || true

    # Unlock vault using master password from environment
    export BW_SESSION=$(${pkgs.bitwarden-cli}/bin/bw unlock --passwordenv BW_PASSWORD --raw)

    # Sync vault
    echo "Syncing Bitwarden vault..."
    ${pkgs.bitwarden-cli}/bin/bw sync || {
      echo "Warning: bw sync failed, using cached data" >&2
    }

    ${concatMapStringsSep "\n" (secret: ''
      echo "Fetching: ${secret.name} from ${secret.itemId}..."
      SECRET_VALUE=$(${fetchItemField} "${secret.itemId}" "${secret.field}")

      if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" = "null" ]; then
        echo "Error: Failed to fetch secret ${secret.name}" >&2
        exit 1
      fi

      # Write secret to file
      echo "$SECRET_VALUE" > "$SECRETS_DIR/${secret.name}"
      chmod ${secret.mode} "$SECRETS_DIR/${secret.name}"
      ${optionalString (secret.owner != null) ''
        chown ${secret.owner} "$SECRETS_DIR/${secret.name}"
      ''}

      echo "  ✓ ${secret.name}"
    '') (attrValues cfg.secrets)}

    echo "Bitwarden secrets sync completed successfully."
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
            description = "Bitwarden item ID or name";
            example = "Tailscale Auth Key";
          };
          field = mkOption {
            type = types.enum [ "password" "notes" "username" ];
            default = "password";
            description = "Which field to extract from the Bitwarden item";
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
      example = literalExpression ''
        {
          tailscale_auth_key = {
            name = "tailscale_auth_key";
            itemId = "Tailscale Auth Key";
            field = "password";
            mode = "0400";
          };
        }
      '';
      description = "Secrets to fetch from Bitwarden at boot time";
    };

    sshKeys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          user = mkOption {
            type = types.str;
            description = "User to own the SSH key";
            example = "scott";
          };
          keyName = mkOption {
            type = types.str;
            description = "SSH key filename (e.g., 'id_ed25519')";
            example = "id_ed25519";
          };
          itemId = mkOption {
            type = types.str;
            description = "Bitwarden item ID or name containing the private key in notes field";
            example = "SSH Key - GitHub";
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
          github = {
            user = "scott";
            keyName = "id_ed25519";
            itemId = "SSH Key - GitHub";
          };
        }
      '';
      description = "SSH keys to fetch from Bitwarden and install to ~/.ssh/";
    };
  };

  config = mkIf cfg.enable {
    # Install Bitwarden CLI
    environment.systemPackages = with pkgs; [
      bitwarden-cli
      jq
    ];

    # Configure sops to decrypt Bitwarden credentials
    sops = {
      defaultSopsFile = cfg.secretsFile;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets."bitwarden/client_id" = {
        mode = "0400";
      };
      secrets."bitwarden/client_secret" = {
        mode = "0400";
      };
      secrets."bitwarden/master_password" = {
        mode = "0400";
      };
    };

    # Systemd service to sync secrets from Bitwarden
    systemd.services.bitwarden-secrets-sync = mkIf (cfg.secrets != {}) {
      description = "Sync secrets from Bitwarden";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = syncScript;
        RemainAfterExit = true;

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/run/bitwarden-secrets" ];
      };

      # Restart on failure
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 300;
      };
    };

    # Timer to periodically refresh secrets (every 6 hours)
    systemd.timers.bitwarden-secrets-sync = mkIf (cfg.secrets != {}) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Unit = "bitwarden-secrets-sync.service";
      };
    };

    # Activation script to install SSH keys at build time
    system.activationScripts.bitwarden-ssh-keys = mkIf (cfg.sshKeys != {}) (
      lib.stringAfter [ "users" ] ''
        echo "Installing SSH keys from Bitwarden..."

        CLIENT_ID_FILE="${config.sops.secrets."bitwarden/client_id".path}"
        CLIENT_SECRET_FILE="${config.sops.secrets."bitwarden/client_secret".path}"
        MASTER_PASSWORD_FILE="${config.sops.secrets."bitwarden/master_password".path}"

        if [ ! -f "$CLIENT_ID_FILE" ] || [ ! -f "$CLIENT_SECRET_FILE" ] || [ ! -f "$MASTER_PASSWORD_FILE" ]; then
          echo "Warning: Bitwarden credential files not found, skipping SSH key installation" >&2
        else
          export BW_CLIENTID=$(cat "$CLIENT_ID_FILE")
          export BW_CLIENTSECRET=$(cat "$CLIENT_SECRET_FILE")
          export BW_PASSWORD=$(cat "$MASTER_PASSWORD_FILE")

          # Login with API key
          ${pkgs.bitwarden-cli}/bin/bw login --apikey --quiet 2>/dev/null || true

          # Unlock vault using master password from environment
          export BW_SESSION=$(${pkgs.bitwarden-cli}/bin/bw unlock --passwordenv BW_PASSWORD --raw)

          # Sync vault first
          ${pkgs.bitwarden-cli}/bin/bw sync 2>/dev/null || true

          ${concatMapStringsSep "\n" (name:
            let
              key = cfg.sshKeys.${name};
              userHome = config.users.users.${key.user}.home;
            in ''
              echo "  Fetching SSH key: ${key.keyName} for ${key.user}..."

              SSH_DIR="${userHome}/.ssh"
              KEY_FILE="$SSH_DIR/${key.keyName}"

              # Create .ssh directory if it doesn't exist
              mkdir -p "$SSH_DIR"

              # Fetch the key from Bitwarden
              # Try .sshKey.privateKey first (for SSH Key type items), then fall back to .notes (for Secure Note items)
              KEY_CONTENT=$(${pkgs.bitwarden-cli}/bin/bw get item "${key.itemId}" | ${pkgs.jq}/bin/jq -r '.sshKey.privateKey // .notes // empty' || echo "")

              if [ -z "$KEY_CONTENT" ] || [ "$KEY_CONTENT" = "null" ]; then
                echo "    Warning: Failed to fetch SSH key ${key.keyName} from Bitwarden" >&2
              else
                # Write the key
                echo "$KEY_CONTENT" > "$KEY_FILE"
                chmod 600 "$KEY_FILE"
                chown ${key.user}:users "$KEY_FILE"
                echo "    ✓ Installed ${key.keyName}"
              fi
            ''
          ) (attrNames cfg.sshKeys)}
        fi
      ''
    );

    # Ensure sops age key exists
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
