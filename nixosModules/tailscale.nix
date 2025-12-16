{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    networking = {
      firewall = {
        allowPing = true;
        allowedUDPPorts = [
          "config.services.tailscale.port"
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
      };
    };
  };
}
