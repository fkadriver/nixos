{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [
      heroic
      # lutris  # pulls in gtk2 (nixpkgs marked it broken, see NixOS/nixpkgs#410814) — not currently used
      wineWow64Packages.stable
      winetricks
    ];
  };
}
