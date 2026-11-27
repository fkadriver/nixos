{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
# Pihole deploys are only ever run from latitude (as caller) or vm01 (as
# cross-build host, see distributed-builds.nix) — see scripts/deploy-piholes.sh.
let
  # Pinned pihole SSH host keys (ed25519) for the deploy script's plain
  # `ssh scott@pihole0X` / `--target-host` calls. The piholes are deliberately
  # not distributed-builds peers, so their keys live here instead. Matched
  # both ssh-keyscan and the tailnet-advertised sshHostKeys on 2026-11-26.
  # After reinstalling a pihole, update its key here (verify with
  # `tailscale status --json | jq '.Peer[] | select(.HostName=="pihole0X") | .sshHostKeys'`).
  piholeHostKeys = {
    pihole01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP6NdhXcnWcan4fmNji2Ig+0q2AGBEsQq/0F6CTTA3k4";
    pihole02 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBAKmCm/NKAhcHaMRb4aMLYi9CEifvx/Ju1j07PnGAkv";
  };
in
{
  config = {
    environment.shellAliases = {
      deploy-piholes = "~/git/nixos/scripts/deploy-piholes.sh";
    };

    programs.ssh.knownHosts = lib.mapAttrs' (name: key:
      lib.nameValuePair "${name}.warthog-royal.ts.net" {
        hostNames = [ name "${name}.warthog-royal.ts.net" ];
        publicKey = key;
      }) piholeHostKeys;
  };
}
