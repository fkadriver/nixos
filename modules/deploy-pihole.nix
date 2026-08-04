{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
# Pihole deploys are only ever run from latitude (as caller) or vm01 (as
# cross-build host, see distributed-builds.nix) — see scripts/deploy-piholes.sh.
{
  config = {
    environment.shellAliases = {
      deploy-piholes = "~/git/nixos/scripts/deploy-piholes.sh";
    };
  };
}
