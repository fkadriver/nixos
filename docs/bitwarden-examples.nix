# Bitwarden Secrets Management - Example Configurations
#
# This file shows different ways to use Bitwarden secrets in your NixOS configuration.
# Copy relevant sections to your host configuration files.

{
  # ============================================================================
  # Example 1: Basic SSH Key Management
  # ============================================================================

  # Enable bitwarden secrets and install SSH keys
  services.bitwarden-secrets = {
    enable = true;
    secretsFile = ../secrets/secrets.yaml;

    sshKeys = {
      # Key name will be the filename in ~/.ssh/
      id_ed25519 = {
        user = "scott";
        secretName = "ssh/github_key";  # Path in secrets.yaml
      };
    };
  };

  # ============================================================================
  # Example 2: Multiple SSH Keys for Different Services
  # ============================================================================

  services.bitwarden-secrets = {
    enable = true;

    sshKeys = {
      id_ed25519 = {
        user = "scott";
        secretName = "ssh/github_key";
      };
      id_rsa_server = {
        user = "scott";
        secretName = "ssh/server_key";
      };
      id_ed25519_gitlab = {
        user = "scott";
        secretName = "ssh/gitlab_key";
      };
    };
  };

  # ============================================================================
  # Example 3: Tailscale with Auth Key from Secrets
  # ============================================================================

  # In your host configuration:
  imports = [
    inputs.self.nixosModules.tailscale
    inputs.self.nixosModules.bitwarden
  ];

  services.bitwarden-secrets.enable = true;

  # Then update modules/tailscale.nix to use the secret:
  # services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth_key".path;

  # ============================================================================
  # Example 4: WiFi Password from Secrets
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  # Update modules/laptop.nix WiFi configuration:
  networking.networkmanager.ensureProfiles = {
    profiles = {
      HOME_WIFI = {
        connection = {
          id = "HOME_WIFI";
          type = "wifi";
          autoconnect = "true";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "YOUR_SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          # Reference the secret file instead of hardcoded password
          psk-flags = "1";  # Read from file
        };
      };
    };
  };

  # Add to sops secrets:
  sops.secrets."wifi/home" = {
    mode = "0400";
  };

  # ============================================================================
  # Example 5: Custom Service with Secret API Key
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  # Define the secret in sops configuration
  sops.secrets."services/my_api_key" = {
    owner = "myservice";
    mode = "0400";
    restartUnits = [ "myservice.service" ];
  };

  # Use in systemd service
  systemd.services.myservice = {
    description = "My Service with Secret API Key";
    serviceConfig = {
      ExecStart = "${pkgs.myapp}/bin/myapp";
      EnvironmentFile = config.sops.secrets."services/my_api_key".path;
      User = "myservice";
    };
  };

  # In secrets.yaml:
  # services:
  #   my_api_key: |
  #     API_KEY=your_secret_key_here

  # ============================================================================
  # Example 6: Syncthing Device Configuration
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  sops.secrets."syncthing/device_id" = {
    owner = "scott";
    mode = "0400";
  };

  # In modules/syncthing.nix, you could reference device IDs
  # services.syncthing.settings.devices = {
  #   "laptop" = {
  #     id = builtins.readFile config.sops.secrets."syncthing/device_id".path;
  #   };
  # };

  # ============================================================================
  # Example 7: Complete Host Configuration with Secrets
  # ============================================================================

  imports = [
    ./latitude-hardware.nix
    inputs.self.nixosModules.common
    inputs.self.nixosModules.laptop
    inputs.self.nixosModules.user-scott
  ];

  services.bitwarden-secrets = {
    enable = true;
    secretsFile = ../secrets/secrets.yaml;

    # Install all SSH keys
    sshKeys = {
      id_ed25519 = {
        user = "scott";
        secretName = "ssh/github_key";
      };
      id_rsa_work = {
        user = "scott";
        secretName = "ssh/work_key";
      };
    };
  };

  # Additional secrets for services
  sops.secrets = {
    "tailscale/auth_key".restartUnits = [ "tailscaled.service" ];
    "wifi/home".mode = "0400";
    "backup/encryption_key" = {
      owner = "scott";
      mode = "0400";
    };
  };

  config = {
    networking.hostName = "latitude-nixos";
    system.stateVersion = "25.04";
  };

  # ============================================================================
  # Example 8: Development Environment with Multiple Secrets
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  # Development secrets
  sops.secrets = {
    "dev/github_token" = {
      owner = "scott";
      mode = "0400";
    };
    "dev/npm_token" = {
      owner = "scott";
      mode = "0400";
    };
    "dev/docker_password" = {
      owner = "scott";
      mode = "0400";
    };
  };

  # Make secrets available in user environment
  home-manager.users.scott = {
    home.sessionVariables = {
      GITHUB_TOKEN = "$(cat ${config.sops.secrets."dev/github_token".path})";
      NPM_TOKEN = "$(cat ${config.sops.secrets."dev/npm_token".path})";
    };
  };

  # ============================================================================
  # Example 9: Server with Database Passwords
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  sops.secrets = {
    "database/postgres_password" = {
      owner = "postgres";
      mode = "0400";
      restartUnits = [ "postgresql.service" ];
    };
    "database/redis_password" = {
      owner = "redis";
      mode = "0400";
      restartUnits = [ "redis.service" ];
    };
  };

  services.postgresql = {
    enable = true;
    authentication = ''
      local all all peer
      host all all 127.0.0.1/32 md5
    '';
    # Use password from secret in initialization scripts
  };

  # ============================================================================
  # Example 10: Per-User Secrets with Home Manager
  # ============================================================================

  services.bitwarden-secrets.enable = true;

  sops.secrets."users/scott/git_signing_key" = {
    owner = "scott";
    mode = "0400";
    path = "/home/scott/.gnupg/git-signing-key.asc";
  };

  home-manager.users.scott = {
    programs.git = {
      enable = true;
      signing = {
        key = "~/.gnupg/git-signing-key.asc";
        signByDefault = true;
      };
    };
  };
}

# ============================================================================
# Corresponding secrets.yaml structure for all examples above:
# ============================================================================

# ssh:
#   github_key: |
#     -----BEGIN OPENSSH PRIVATE KEY-----
#     ...
#     -----END OPENSSH PRIVATE KEY-----
#   server_key: |
#     -----BEGIN OPENSSH PRIVATE KEY-----
#     ...
#     -----END OPENSSH PRIVATE KEY-----
#   work_key: |
#     -----BEGIN OPENSSH PRIVATE KEY-----
#     ...
#     -----END OPENSSH PRIVATE KEY-----
#
# tailscale:
#   auth_key: tskey-auth-xxxxx-xxxxxx
#
# wifi:
#   home: your_wifi_password
#
# services:
#   my_api_key: |
#     API_KEY=sk_live_xxxxxxxxx
#
# syncthing:
#   device_id: XXXXXXX-XXXXXXX-XXXXXXX
#
# backup:
#   encryption_key: your_backup_encryption_passphrase
#
# dev:
#   github_token: ghp_xxxxxxxxxxxxxxxxxxxx
#   npm_token: npm_xxxxxxxxxxxxxxxxxxxxxx
#   docker_password: dckr_pat_xxxxxxxxxxx
#
# database:
#   postgres_password: super_secure_password
#   redis_password: another_secure_password
#
# users:
#   scott:
#     git_signing_key: |
#       -----BEGIN PGP PRIVATE KEY BLOCK-----
#       ...
#       -----END PGP PRIVATE KEY BLOCK-----
