{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.bitwarden-secrets;
in
{
  options.services.bitwarden-secrets = {
    enable = mkEnableOption "Bitwarden secrets management with sops-nix";

    secretsFile = mkOption {
      type = types.path;
      default = ../secrets/secrets.yaml;
      description = "Path to the encrypted secrets.yaml file";
    };

    sshKeys = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          user = mkOption {
            type = types.str;
            default = "scott";
            description = "User to own the SSH key";
          };
          secretName = mkOption {
            type = types.str;
            description = "Name of the secret in secrets.yaml";
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
          github = {
            user = "scott";
            secretName = "ssh/github_key";
          };
        }
      '';
      description = "SSH keys to install from secrets";
    };
  };

  config = mkIf cfg.enable {
    # Install Bitwarden CLI and sops tools
    environment.systemPackages = with pkgs; [
      bitwarden-cli  # Official Bitwarden CLI (bw)
      sops           # Secrets editor
      age            # Encryption tool
      ssh-to-age     # Convert SSH keys to age keys
    ];

    # Import sops-nix module
    imports = [ inputs.sops-nix.nixosModules.sops ];

    # Configure sops
    sops = {
      defaultSopsFile = cfg.secretsFile;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      # Define secrets that will be available to the system
      secrets = {
        # Tailscale auth key
        "tailscale/auth_key" = {
          restartUnits = [ "tailscaled.service" ];
        };

        # SSH keys (defined dynamically based on configuration)
      } // (mapAttrs' (name: value: nameValuePair
        value.secretName
        {
          owner = value.user;
          mode = "0600";
          path = "/home/${value.user}/.ssh/${name}";
        }
      ) cfg.sshKeys);
    };

    # Helper script to extract secrets from Bitwarden
    environment.etc."bitwarden-extract-secrets.sh" = {
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        # Bitwarden to sops-nix secret extraction script
        # This script helps extract secrets from Bitwarden and format them for sops-nix

        echo "=== Bitwarden Secret Extraction Tool ==="
        echo ""
        echo "This script will help you extract secrets from Bitwarden"
        echo "and save them in the sops-nix encrypted format."
        echo ""

        # Check if logged into Bitwarden
        if ! bw status | grep -q '"status":"unlocked"'; then
          echo "Please log in to Bitwarden first:"
          echo "  export BW_SESSION=\$(bw login --raw)"
          echo "  # or if already logged in:"
          echo "  export BW_SESSION=\$(bw unlock --raw)"
          exit 1
        fi

        SECRETS_FILE="''${1:-secrets/secrets.yaml}"
        mkdir -p "$(dirname "$SECRETS_FILE")"

        echo "Extracting secrets to: $SECRETS_FILE"
        echo ""

        # Create YAML template
        cat > "''${SECRETS_FILE}.tmp" <<'YAML'
        # Tailscale authentication key
        # Get from: https://login.tailscale.com/admin/settings/keys
        tailscale:
          auth_key: YOUR_TAILSCALE_AUTH_KEY

        # SSH keys stored in Bitwarden
        # Format: Store the private key content in Bitwarden notes
        ssh:
          github_key: |
            -----BEGIN OPENSSH PRIVATE KEY-----
            YOUR_SSH_PRIVATE_KEY_HERE
            -----END OPENSSH PRIVATE KEY-----

          server_key: |
            -----BEGIN OPENSSH PRIVATE KEY-----
            YOUR_SERVER_SSH_KEY_HERE
            -----END OPENSSH PRIVATE KEY-----

        # Syncthing configuration
        syncthing:
          device_id: YOUR_SYNCTHING_DEVICE_ID

        # WiFi passwords
        wifi:
          home: YOUR_WIFI_PASSWORD
        YAML

        echo "Template created at: ''${SECRETS_FILE}.tmp"
        echo ""
        echo "Next steps:"
        echo "  1. Edit the template with your actual secrets"
        echo "  2. Use Bitwarden CLI to fetch secrets:"
        echo "       bw get item 'SSH Key - GitHub' | jq -r '.notes'"
        echo "  3. Encrypt with sops (see documentation)"
        echo ""
      '';
      mode = "0755";
    };

    # System activation script to ensure sops key exists
    system.activationScripts.sops-nix-setup = lib.mkIf cfg.enable ''
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
