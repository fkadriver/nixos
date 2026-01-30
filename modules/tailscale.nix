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
        # Auto-authenticate using auth key from secrets
        # Supports both old (sops-based) and new (dynamic Bitwarden) approaches
        authKeyFile =
          if (config.services ? bitwarden-dynamic && config.services.bitwarden-dynamic.enable)
          then "/run/bitwarden-secrets/tailscale_auth_key"
          else if (config.services ? bitwarden-secrets && config.services.bitwarden-secrets.enable)
          then config.sops.secrets."tailscale/auth_key".path
          else null;
      };
    };
  };
}
