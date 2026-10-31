{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    services = {
      syncthing = {
        dataDir = "/home/scott";
        enable = true;
        # Standalone daemon, no system coupling — fine on the
        # better-cached nixos-unstable input.
        package = inputs.nixpkgs-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.syncthing;
        overrideDevices = false;
        overrideFolders = false;
        user = "scott";
      };
    };
  };
}
