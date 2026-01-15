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
        # Auto-authenticate using auth key from secrets (if bitwarden-secrets is enabled)
        authKeyFile = lib.mkIf
          (config.services ? bitwarden-secrets && config.services.bitwarden-secrets.enable)
          config.sops.secrets."tailscale/auth_key".path;
      };
    };
  };
}
