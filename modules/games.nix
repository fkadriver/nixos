{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  # Heroic 2.20.0 via AppImage (nixpkgs ships 2.19.1 built from source)
  heroic-2_20 = pkgs.appimageTools.wrapType2 {
    pname = "heroic";
    version = "2.20.0";
    src = pkgs.fetchurl {
      url = "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.20.0/Heroic-2.20.0-linux-x86_64.AppImage";
      hash = "sha256-tw9UNh1+eK6Sx7sRTmSgdaWxzakQ0akAB7pobOuzYOE=";
    };
    meta = {
      description = "Epic, GOG, and Amazon Prime Games launcher";
      homepage = "https://heroicgameslauncher.com";
      license = lib.licenses.gpl3Only;
      platforms = [ "x86_64-linux" ];
      mainProgram = "heroic";
    };
  };
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
