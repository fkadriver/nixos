{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  # Heroic 2.20.0 - nixpkgs ships 2.19.1, override to 2.20.0
  # pnpm-lock.yaml changed between releases so pnpmDeps hash must be updated.
  # To get the correct pnpmDeps hash:
  #   sudo nixos-rebuild switch --flake .#<hostname>
  # The build will fail with "got: sha256-..." — paste that hash below.
  heroic-2_20 =
    let
      newSrc = pkgs.fetchFromGitHub {
        owner = "Heroic-Games-Launcher";
        repo = "HeroicGamesLauncher";
        tag = "v2.20.0";
        hash = "sha256-gjQPQ/PwpDlBUfNF1JAlWUDGJa+7hwoQtouihdSCDqI=";
      };
      newUnwrapped = pkgs.heroic-unwrapped.overrideAttrs (old: {
        version = "2.20.0";
        src = newSrc;
        pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
          # PLACEHOLDER: replace with hash from build error output
          hash = lib.fakeHash;
        });
      });
    in
      pkgs.heroic.override { heroic-unwrapped = newUnwrapped; };
in
{
  config = {
    environment.systemPackages = with pkgs; [
      heroic-2_20
      lutris
      wineWowPackages.stable
      winetricks
    ];
  };
}
