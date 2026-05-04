{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      heroic
      lutris
      wineWow64Packages.stable
      winetricks
    ];
  };
}
