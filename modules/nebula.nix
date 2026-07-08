# Nebula overlay network (mesh) — Tailscale replacement in progress
#
# Overlay subnet: 10.100.0.0/24, network name "mesh" (interface nebula.mesh).
# Certs: public certs live in ../secrets/nebula/*.crt (committed plaintext);
# private keys are sops-encrypted in secrets.yaml under nebula/<host>_key.
# The CA private key (nebula/ca_key) never leaves secrets.yaml — see
# docs/nebula.md for how to sign certs for new hosts.
#
# Lighthouses:
#   - vm01 (10.100.0.3) — always-on LAN lighthouse at 192.168.10.21
#   - lighthouse01 (10.100.0.1) — Oracle Cloud Always Free instance for
#     roaming; cert/key already issued. Uncomment its entries below and fill
#     in the public IP once the instance exists (see docs/nebula.md).
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  hostName = config.networking.hostName;

  # Every host on the mesh. Signing a cert for a new host? Add it here too.
  meshHosts = {
    lighthouse01 = "10.100.0.1";
    latitude = "10.100.0.2";
    vm01 = "10.100.0.3";
  };

  lighthouseIPs = [
    meshHosts.vm01
    # meshHosts.lighthouse01
  ];

  # Lighthouses (and any host with a stable address) get a fixed endpoint here
  # so other nodes can find them without discovery. vm01's 192.168.10.21 is a
  # static lease in the OPNsense firewall.
  staticHostMap = {
    "${meshHosts.vm01}" = [ "192.168.10.21:4242" ];
    # "${meshHosts.lighthouse01}" = [ "LIGHTHOUSE01_PUBLIC_IP:4242" ];
  };

  meshIP = meshHosts.${hostName} or (throw
    "nebula.nix: host '${hostName}' has no mesh IP — add it to meshHosts and sign a cert (docs/nebula.md)");
  isLighthouse = builtins.elem meshIP lighthouseIPs;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  config = {
    sops.age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
    sops.secrets."nebula/${hostName}_key" = {
      sopsFile = ../secrets/secrets.yaml;
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0400";
      restartUnits = [ "nebula@mesh.service" ];
    };

    services.nebula.networks.mesh = {
      enable = true;
      ca = ../secrets/nebula/ca.crt;
      cert = ../secrets/nebula + "/${hostName}.crt";
      key = config.sops.secrets."nebula/${hostName}_key".path;

      inherit isLighthouse staticHostMap;
      # Lighthouses don't query other lighthouses
      lighthouses = lib.optionals (!isLighthouse) lighthouseIPs;

      settings = {
        punchy = {
          punch = true;
          respond = true; # helps when both sides are behind NAT
        };
      };

      # Cert possession is the gate (same trust model as the Tailscale setup,
      # where tailscale0 is a trusted interface); allow everything inside the mesh.
      firewall = {
        outbound = [ { port = "any"; proto = "any"; host = "any"; } ];
        inbound = [ { port = "any"; proto = "any"; host = "any"; } ];
      };
    };

    # Nebula's own firewall governs mesh traffic; don't double-filter in nftables
    networking.firewall.trustedInterfaces = [ "nebula.mesh" ];

    # Name resolution until a DNS story is picked: <host>.mesh
    networking.hosts = lib.mapAttrs' (name: ip: lib.nameValuePair ip [ "${name}.mesh" ]) meshHosts;
  };
}
