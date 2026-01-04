{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      shellAliases = {
        # Basic
        wtf = "alias";
        clr = "clear";

        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        slap = "tailscale ssh latitude-nixos";
        log01 = "tailscale ssh sands-log01";

        # Grep with color
        gpc = "grep --color=always";

        # NIX commands
        rebuild = "sudo nixos-rebuild switch --flake ";
      };
    };
  };
}
