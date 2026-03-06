{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      heroic
      lutris
      wineWowPackages.stable
      winetricks
    ];
  };
}
