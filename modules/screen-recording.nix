{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    simplescreenrecorder
  ];
}
