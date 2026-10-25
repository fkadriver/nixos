{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  services.bitwarden.secrets.container_ts_authkey = {
    name = "container_ts_authkey";
    itemId = "3fcd8301-f2b8-4376-a4cc-b48d015b1ea5";  # BW_Name: Tailscale Container AUTH key
    field = "ts_authkey";
    mode = "0400";
  };

  # Shared ExecStart for every docker-compose Tailscale sidecar
  # (tailscale/tailscale image). All of them must source TS_AUTHKEY from
  # this one Bitwarden-managed key via /run/bitwarden-secrets — never a
  # hardcoded value in a local .env — so rotating the key (Tailscale caps
  # reusable keys at 90 days) fixes every sidecar at once instead of only
  # whichever one someone remembered to update. Current users: unifi-docker
  # and immich-docker (vm01), immich-ml-docker (latitude), wazuh-docker
  # (log01). Any new docker-compose Tailscale sidecar should use this too:
  #   requires = [ "bitwarden-secrets-sync.service" "docker.service" ];
  #   after = [ "bitwarden-secrets-sync.service" "docker.service" "network-online.target" ];
  #   serviceConfig = {
  #     WorkingDirectory = "<repo path>";
  #     ExecStart = tsDockerSidecarStart;
  #     ExecStop = "${pkgs.docker}/bin/docker compose down";
  #   };
  # (requires adding `tsDockerSidecarStart` to that host's module argument list)
  _module.args.tsDockerSidecarStart =
    pkgs.writeShellScript "ts-docker-sidecar-start" ''
      set -euo pipefail
      export TS_AUTHKEY=$(cat /run/bitwarden-secrets/container_ts_authkey)
      exec ${pkgs.docker}/bin/docker compose up -d
    '';
}
