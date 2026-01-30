# Example configuration using dynamic Bitwarden secrets
# This shows how to configure a host to use bitwarden-dynamic module

{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  imports = [
    # Your hardware configuration
    ./hardware-configuration.nix

    # Common modules
    ../modules/common.nix
    ../modules/user-scott.nix

    # Required for dynamic Bitwarden secrets
    # (module is auto-imported, no need to import manually)
  ];

  # Enable dynamic Bitwarden secrets management
  services.bitwarden-dynamic = {
    enable = true;

    # SSH keys to fetch from Bitwarden and install to ~/.ssh/
    sshKeys = {
      # GitHub SSH key
      github = {
        user = "scott";
        keyName = "id_ed25519";
        # Item ID can be UUID or exact item name
        itemId = "SSH Key - GitHub";
      };

      # Legacy servers SSH key
      legacy = {
        user = "scott";
        keyName = "id_ed25519_legacy";
        itemId = "SSH Key - Legacy Servers";
      };
    };

    # Other secrets (non-SSH) that will be available in /run/bitwarden-secrets/
    secrets = {
      # Tailscale authentication key
      tailscale_auth_key = {
        name = "tailscale_auth_key";
        itemId = "Tailscale Auth Key";
        field = "password";  # For Login items, use "password"; for Secure Notes, use "notes"
        mode = "0400";       # Read-only by root
      };

      # Example: Database password
      # postgres_password = {
      #   name = "postgres_password";
      #   itemId = "PostgreSQL Admin Password";
      #   field = "password";
      #   mode = "0400";
      # };

      # Example: API key stored in notes
      # api_key = {
      #   name = "my_api_key";
      #   itemId = "My Service API Key";
      #   field = "notes";  # If stored in notes field
      #   mode = "0400";
      # };
    };
  };

  # Other system configuration...
  networking.hostName = "example-host";
  system.stateVersion = "24.05";
}
