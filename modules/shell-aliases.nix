{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
# MAINTENANCE: When updating aliases here, also update:
#   - Darwin: hosts/airbook-darwin/home.nix
#             (programs.bash.shellAliases / programs.zsh.shellAliases)
# Rebuild aliases by host:
#   nix-rebuild  → latitude, vm01 (nixos-rebuild), airbook (darwin-rebuild)
{
  config = {
    environment = {
      shellAliases = {
        # Basic
        wtf = "alias";
        clr = "clear";
        ipa = "ip -o -4 a";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        airbook = "tailscale ssh airbook";
        nas01 = "tailscale ssh nas01";
        log01 = "tailscale ssh log01";
        pihole01 = "tailscale ssh pihole01";
        pihole02 = "tailscale ssh pihole02";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
        vm01 = "tailscale ssh vm01";
        OTworkstation = "tailscale ssh OTworkstation";
        otworkstation = "tailscale ssh OTworkstation";
        ot = "tailscale ssh OTworkstation";

        # Tailscale troubleshooting
        ts-status = "tailscale status";
        ts-up = "sudo tailscale up";
        ts-down = "sudo tailscale down";
        ts-netcheck = "tailscale netcheck";
        ts-ip = "tailscale ip";
        ts-peers = "tailscale status --peers";
        ts-self = "tailscale status --self";
        ts-debug = "tailscale debug";

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
	nixdir = "cd ~/git/nixos";
        nix-build-test = "nix flake check";
        nix-update = "nix flake update";
        nix-search = "nix search nixpkgs";
        nix-shell-python = "nix-shell -p python3 python3Packages.pip";

        # NixOS system shortcuts with automatic hostname detection
        nix-rebuild = "_d=$PWD; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd ~/git/nixos; GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git pull && sudo nixos-rebuild switch --flake ~/git/nixos#$(hostname); [ \"$_d\" != \"$HOME/git/nixos\" ] && cd -; unset _d; source ~/.bashrc";
        nix-sync = "~/git/nixos/scripts/sync-nixos-hosts.sh";
        nos-rebuild = "sudo nixos-rebuild switch --flake .";
        nos-test = "sudo nixos-rebuild test --flake .";
        nos-boot = "sudo nixos-rebuild boot --flake .";
        nos-clean = "sudo nix-collect-garbage -d";
        nos-optimize = "sudo nix-store --optimize";
        nos-list-gens = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Temperature monitoring
        temps = ''echo '=== CPU Temps (°F) ===' && sensors -f 2>/dev/null | grep -E ':.*°F' || echo '(run: sudo sensors-detect)'; echo ""; echo '=== Drive Temps (°F) ==='; for d in /dev/sd?; do C=$(sudo smartctl -A "$d" 2>/dev/null | awk '/^[[:space:]]*19[04] /{print $10}' | head -1); if [ -n "$C" ]; then printf "%s: %d°F\n" "$d" "$((C * 9 / 5 + 32))"; else printf "%s: N/A\n" "$d"; fi; done'';

        # IDrive360 — DEB container (Ubuntu, nas01)
        idrive-deb-log     = "ssh nas01 journalctl -u docker-idrive360-deb -f";
        idrive-deb-ps      = "ssh nas01 docker exec idrive360-deb ps aux";
        idrive-deb-stop    = "ssh nas01 sudo systemctl stop docker-idrive360-deb";
        idrive-deb-start   = "ssh nas01 sudo systemctl start docker-idrive360-deb";
        idrive-deb-restart = "ssh nas01 sudo systemctl restart docker-idrive360-deb";
        idrive-deb-kill    = "ssh nas01 \"docker exec -u scott idrive360-deb /opt/IDrive360/idrive360 --terminate-job backup - 2\"";

        # IDrive360 — RPM container (Rocky Linux, nas01)
        idrive-rpm-log     = "ssh nas01 journalctl -u docker-idrive360-rpm -f";
        idrive-rpm-ps      = "ssh nas01 docker exec idrive360-rpm ps aux";
        idrive-rpm-stop    = "ssh nas01 sudo systemctl stop docker-idrive360-rpm";
        idrive-rpm-start   = "ssh nas01 sudo systemctl start docker-idrive360-rpm";
        idrive-rpm-restart = "ssh nas01 sudo systemctl restart docker-idrive360-rpm";
        idrive-rpm-kill    = "ssh nas01 \"docker exec -u scott idrive360-rpm /opt/IDrive360/idrive360 --terminate-job backup - 2\"";

        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

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
