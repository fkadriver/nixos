{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  imports = [ inputs.sops-nix.nixosModules.sops ];

  config = {
    # gh (GitHub CLI) fails to cross-compile for aarch64 due to a -m64 flag bug.
    # Pi-hole servers don't need it — replace with an empty stub for aarch64 builds.
    nixpkgs.overlays = [
      (final: prev: lib.optionalAttrs prev.stdenv.hostPlatform.isAarch64 {
        gh = prev.runCommandLocal "gh-stub" {} "mkdir -p $out";
      })
    ];
    # Pi-hole owns port 53 — disable resolved's stub listener so it doesn't conflict.
    # resolved is enabled by tailscale.nix (imported by common.nix), so we force it off here.
    services.resolved = lib.mkForce { enable = false; };

    # Use Pi-hole for local DNS with Quad9 as an out-of-band fallback during boot
    networking.nameservers = lib.mkDefault [ "127.0.0.1" "9.9.9.9" ];

    # Pi-hole FTL daemon
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;

      # Block and allow lists — managed here; user-added lists via Pi-Remote persist in gravity.db
      lists = [
        {
          url = "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/adblock/multi.txt";
          type = "block";
          enabled = true;
          description = "Hagezi Multi blocklist";
        }
        {
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/adblock/whitelist-referral-native.txt";
          type = "allow";
          enabled = true;
          description = "Hagezi Referral Native allowlist";
        }
      ];

      settings = {
        dns = {
          upstreams = [ "9.9.9.9" "149.112.112.112" ];
          dnssec = true;
        };
        # pihole.toml is regenerated on each rebuild — block API config changes from the web UI
        misc.readOnly = true;
      };
    };

    # Pi-hole web admin interface (ports: plain number = HTTP, "Ns" suffix = HTTPS)
    services.pihole-web = {
      enable = true;
      ports = [ "80" ];
    };

    # Open HTTP/HTTPS for the web UI (pihole-web handles ports, but firewall must allow them)
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # Password hash injected via environment variable so it survives nixos-rebuild.
    # FTLCONF_ env vars override the corresponding pihole.toml settings at runtime.
    # Store the bcrypt hash in secrets.yaml as pihole/pwhash.
    # Generate with: pihole setpassword, then read webserver.api.pwhash from /etc/pihole/pihole.toml
    sops = {
      defaultSopsFile = lib.mkDefault ../secrets/secrets.yaml;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets."pihole/pwhash" = {};

      templates."pihole-ftl-env" = {
        content = "FTLCONF_webserver_api_pwhash=${config.sops.placeholder."pihole/pwhash"}\n";
        owner = config.services.pihole-ftl.user;
        mode = "0400";
      };
    };

    # Feed the password hash to pihole-ftl without baking it into the nix store
    systemd.services.pihole-ftl.serviceConfig.EnvironmentFile =
      [ config.sops.templates."pihole-ftl-env".path ];
  };
}
