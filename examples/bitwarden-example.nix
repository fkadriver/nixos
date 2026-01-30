# Example Bitwarden configuration
#
# This example shows how to configure SSH keys and service secrets
# using the Bitwarden module.

{ config, lib, pkgs, ... }: {
  imports = [
    ../modules/bitwarden.nix
  ];

  services.bitwarden = {
    enable = true;

    # SSH keys are fetched at build time and written to ~/.ssh/
    sshKeys = {
      # Primary SSH key (e.g., for GitHub, GitLab)
      github = {
        user = "scott";               # Your username
        keyName = "id_ed25519";       # Filename in ~/.ssh/
        itemId = "SSH Key - GitHub";  # Bitwarden item name or UUID
      };

      # Additional SSH key (e.g., for legacy servers)
      legacy = {
        user = "scott";
        keyName = "id_ed25519_legacy";
        itemId = "SSH Key - Legacy Servers";
      };
    };

    # Service secrets are fetched at boot and written to /run/bitwarden-secrets/
    # They are automatically refreshed every 6 hours
    secrets = {
      # Tailscale authentication key
      tailscale_auth_key = {
        name = "tailscale_auth_key";        # Filename in /run/bitwarden-secrets/
        itemId = "Tailscale Auth Key";      # Bitwarden item name or UUID
        field = "password";                 # Extract from password field
        mode = "0400";                      # File permissions
      };

      # Example: Database password
      # postgres_password = {
      #   name = "postgres_password";
      #   itemId = "PostgreSQL Production";
      #   field = "password";
      #   mode = "0400";
      # };

      # Example: API token stored in notes
      # api_token = {
      #   name = "my_api_token";
      #   itemId = "External API Token";
      #   field = "notes";
      #   mode = "0400";
      # };
    };
  };

  # Example: Tailscale using the fetched auth key
  services.tailscale = {
    enable = true;
    authKeyFile = lib.mkIf config.services.bitwarden.enable
      "/run/bitwarden-secrets/tailscale_auth_key";
  };
}
