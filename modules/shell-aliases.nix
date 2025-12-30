{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      shellAliases = {
        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        slap = "tailscale ssh latitude-nixos";
        log01 = "tailscale ssh sands-log01";

        # Grep with color
        gpc = "grep --color=always";
      };
    };
  };
}
