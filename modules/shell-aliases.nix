{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      shellAliases = {
        # Basic
        wtf = "alias";
        clr = "clear";

        # Tailscale SSH shortcuts
        airbook = "tailscale ssh airbook";
        nas01 = "tailscale ssh nas01";
        slap = "tailscale ssh latitude";
        log01 = "tailscale ssh sands-log01";

        # Grep with color
        gpc = "grep --color=always";

        # Git shortcuts
        g = "git";
        gs = "git status";
        ga = "git add";
        gaa = "git add -A";
        gc = "git commit";
        gcm = "git commit -m";
        gp = "git push";
        gpl = "git pull";
        gd = "git diff";
        gdc = "git diff --cached";
        gl = "git log --oneline --graph --decorate";
        gla = "git log --oneline --graph --decorate --all";
        gco = "git checkout";
        gb = "git branch";
        gba = "git branch -a";
        gf = "git fetch";
        gr = "git restore";
        grs = "git restore --staged";

        # Nix shortcuts
        nix-build-test = "nix flake check";
        nix-update = "nix flake update";
        nix-search = "nix search nixpkgs";
        nix-shell-python = "nix-shell -p python3 python3Packages.pip";

        # NixOS system shortcuts with automatic hostname detection
        rebuild = ''
          case "$(hostname)" in
            latitude) sudo nixos-rebuild switch --flake .#latitude ;;
            airbook) sudo nixos-rebuild switch --flake .#airbook ;;
            *) echo "Unknown hostname: $(hostname)"; sudo nixos-rebuild switch --flake . ;;
          esac
        '';
        nos-rebuild = "sudo nixos-rebuild switch --flake .";
        nos-test = "sudo nixos-rebuild test --flake .";
        nos-boot = "sudo nixos-rebuild boot --flake .";
        nos-clean = "sudo nix-collect-garbage -d";
        nos-optimize = "sudo nix-store --optimize";
        nos-list-gens = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";

        # Common utilities
        ll = "ls -lah";
        la = "ls -A";
        l = "ls -CF";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
      };
    };
  };
}
