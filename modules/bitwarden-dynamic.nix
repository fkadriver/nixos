{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.bitwarden-dynamic;

  # Helper script to fetch secrets from Bitwarden
  fetchSecret = pkgs.writeShellScript "bw-fetch-secret" ''
    set -euo pipefail

    BW_SESSION_FILE="$1"
    ITEM_ID="$2"
    FIELD="$3"  # "password" or "notes"

    if [ ! -f "$BW_SESSION_FILE" ]; then
      echo "Error: BW_SESSION file not found: $BW_SESSION_FILE" >&2
      exit 1
    fi

    export BW_SESSION=$(cat "$BW_SESSION_FILE")

    # Fetch the item and extract the field
    ${pkgs.bitwarden-cli}/bin/bw get item "$ITEM_ID" | ${pkgs.jq}/bin/jq -r ".$FIELD" || {
      echo "Error: Failed to fetch secret from Bitwarden (item: $ITEM_ID, field: $FIELD)" >&2
      exit 1
    }
  '';

  # Systemd service to sync secrets from Bitwarden
  syncScript = pkgs.writeShellScript "bw-sync-secrets" ''
    set -euo pipefail

    BW_SESSION_FILE="${config.sops.secrets."bitwarden/session".path}"
    SECRETS_DIR="/run/bitwarden-secrets"

    if [ ! -f "$BW_SESSION_FILE" ]; then
      echo "Error: BW_SESSION file not found. Bitwarden secrets sync cannot proceed." >&2
      exit 1
    fi

    export BW_SESSION=$(cat "$BW_SESSION_FILE")

    # Ensure secrets directory exists
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    echo "Syncing Bitwarden vault..."
    ${pkgs.bitwarden-cli}/bin/bw sync || {
      echo "Warning: bw sync failed, using cached data" >&2
    }

    ${concatMapStringsSep "\n" (secret: ''
      echo "Fetching: ${secret.name} from ${secret.itemId}..."
      SECRET_VALUE=$(${fetchSecret} "$BW_SESSION_FILE" "${secret.itemId}" "${secret.field}")

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

  options.services.bitwarden-dynamic = {
    enable = mkEnableOption "Dynamic Bitwarden secrets management";

    sessionKeyFile = mkOption {
      type = types.path;
      default = ../secrets/secrets.yaml;
      description = "Path to the encrypted secrets.yaml containing BW_SESSION";
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
            example = "a1b2c3d4-1234-5678-abcd-ef1234567890";
          };
          field = mkOption {
            type = types.enum [ "password" "notes" ];
            default = "notes";
            description = "Which field to extract from the Bitwarden item";
          };
          mode = mkOption {
            type = types.str;
            default = "0600";
            description = "File permissions for the secret";
          };
          owner = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Owner of the secret file";
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
          };
        }
      '';
      description = "Secrets to fetch from Bitwarden";
    };

    sshKeys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          user = mkOption {
            type = types.str;
            default = "scott";
            description = "User to own the SSH key";
          };
          keyName = mkOption {
            type = types.str;
            description = "SSH key filename (e.g., 'id_ed25519')";
          };
          itemId = mkOption {
            type = types.str;
            description = "Bitwarden item ID or name containing the private key";
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

    # Configure sops to only decrypt the Bitwarden session key
    sops = {
      defaultSopsFile = cfg.sessionKeyFile;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets."bitwarden/session" = {
        mode = "0400";
      };
    };

    # Systemd service to sync secrets from Bitwarden
    systemd.services.bitwarden-secrets-sync = {
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
        ProtectHome = false;  # Need access to write SSH keys
        ReadWritePaths = [ "/run/bitwarden-secrets" ];
      };

      # Restart on failure
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 300;
      };
    };

    # Timer to periodically refresh secrets (every 6 hours)
    systemd.timers.bitwarden-secrets-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Unit = "bitwarden-secrets-sync.service";
      };
    };

    # Activation script to install SSH keys
    system.activationScripts.bitwarden-ssh-keys = lib.mkIf (cfg.sshKeys != {}) (
      lib.stringAfter [ "users" ] ''
        echo "Installing SSH keys from Bitwarden..."

        BW_SESSION_FILE="${config.sops.secrets."bitwarden/session".path}"

        if [ ! -f "$BW_SESSION_FILE" ]; then
          echo "Warning: BW_SESSION file not found, skipping SSH key installation" >&2
        else
          export BW_SESSION=$(cat "$BW_SESSION_FILE")

          # Sync vault first
          ${pkgs.bitwarden-cli}/bin/bw sync 2>/dev/null || true

          ${concatMapStringsSep "\n" (name:
            let
              key = cfg.sshKeys.${name};
            in ''
              echo "  Fetching SSH key: ${key.keyName} for ${key.user}..."

              USER_HOME=$(${pkgs.coreutils}/bin/su - ${key.user} -c 'echo $HOME')
              SSH_DIR="$USER_HOME/.ssh"
              KEY_FILE="$SSH_DIR/${key.keyName}"

              # Create .ssh directory if it doesn't exist
              mkdir -p "$SSH_DIR"

              # Fetch the key from Bitwarden
              KEY_CONTENT=$(${pkgs.bitwarden-cli}/bin/bw get item "${key.itemId}" | ${pkgs.jq}/bin/jq -r '.notes' || echo "")

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

    # Ensure sops key exists
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
