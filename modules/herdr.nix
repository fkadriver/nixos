{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  # Herdr — terminal workspace manager for AI coding agents (herdr.dev). Not
  # in nixpkgs; ships only as a prebuilt binary, so fetch the release asset
  # directly (same reasoning as modules/kali-docker.nix reaching outside
  # nixpkgs for Kali). `ldd` on the fetched binary reports "statically
  # linked" — no shared-library deps, so no autoPatchelf/buildInputs needed,
  # unlike most prebuilt-binary packages. No account/login required.
  #
  # `herdr --remote <ssh-target>` attaches through SSH to a Herdr server on
  # another machine, the way `tmux attach` attaches to a local session — see
  # the -h aliases in modules/daily-driver.nix. Pinned to v0.9.5; bump the
  # version and sha256 together from https://herdr.dev/latest.json.
  version = "0.9.5";
  herdr = pkgs.stdenvNoCC.mkDerivation {
    pname = "herdr";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64";
      sha256 = "14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/herdr
    '';
    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://herdr.dev";
      platforms = [ "x86_64-linux" ];
      mainProgram = "herdr";
    };
  };
in
{
  config = {
    environment.systemPackages = [ herdr ];
  };
}
