{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    networking = {
      firewall = {
        allowPing = true;
        allowedUDPPorts = [
          config.services.tailscale.port
        ];
        enable = true;
        trustedInterfaces = [
          "tailscale0"
        ];
      };
    };
    services = {
      resolved = {
        dnsovertls = "opportunistic";
        dnssec = "allow-downgrade";
        enable = true;
      };
      tailscale = {
        enable = true;
        useRoutingFeatures = "both";
        extraUpFlags = [
          "--accept-routes"
          "--ssh"
        ];
        # Auto-authenticate using auth key from Bitwarden secrets
        # The key is fetched from Bitwarden and stored at /run/bitwarden-secrets/
        authKeyFile =
          if (config.services ? bitwarden && config.services.bitwarden.enable && config.services.bitwarden.secrets ? tailscale_auth_key)
          then "/run/bitwarden-secrets/tailscale_auth_key"
          else null;
      };
    };
  };
}
