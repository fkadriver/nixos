# Pull-through cache for the fleet's substituters (cache.nixos.org,
# nix-community.cachix.org). First request for a store path pays the
# internet fetch and caches it on ZFS; every other host then substitutes
# from here instead of re-downloading. Signatures pass through untouched
# (nginx just proxies bytes), so clients keep verifying against the real
# upstream keys — no separate signing setup needed, unlike the peer-to-peer
# sharing in distributed-builds.nix (which caches locally-*built* paths,
# not internet substitutes).
#
# Dataset must exist before first activation:
#   sudo zfs create -o compression=lz4 pool/nix-cache
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    services.nginx = {
      enable = true;
      commonHttpConfig = ''
        proxy_cache_path /pool/nix-cache/nginx levels=1:2 keys_zone=nixcache:100m max_size=250g inactive=60d use_temp_path=off;
      '';
      virtualHosts."nix-cache-proxy" = {
        listen = [ { addr = "0.0.0.0"; port = 8383; } ];
        locations = lib.genAttrs
          [ "/cache.nixos.org/" "/nix-community.cachix.org/" ]
          (path: let host = lib.removeSuffix "/" path; in {
            proxyPass = "https://${lib.removePrefix "/" host}/";
            extraConfig = ''
              proxy_ssl_server_name on;
              proxy_set_header Host ${lib.removePrefix "/" host};
              proxy_cache nixcache;
              proxy_cache_valid 200 302 24h;
              proxy_cache_valid 404 5m;
              proxy_cache_key $scheme$proxy_host$uri$is_args$args;
              proxy_cache_lock on;
            '';
          });
      };
    };

    # tailscale0 is already a trustedInterfaces entry (modules/tailscale.nix),
    # so this is belt-and-suspenders — matches the syncthing GUI precedent.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8383 ];

    # NixOS's nginx unit runs under ProtectSystem=strict — the whole filesystem
    # is read-only to the service except paths listed here, so without this
    # nginx's own mkdir for proxy_cache_path fails with EROFS despite /pool
    # being rw at the system level.
    systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/pool/nix-cache" ];

    systemd.tmpfiles.rules = [
      "d /pool/nix-cache 0750 nginx nginx -"
    ];
  };
}
