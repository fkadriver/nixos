{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      heroic
      wineWow64Packages.stable
      winetricks
    ];
  };
}
