{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
# MAINTENANCE: When updating aliases here, also update:
#   - Darwin: hosts/airbook-darwin/home.nix
#             (programs.bash.shellAliases / programs.zsh.shellAliases)
#   - Standalone home-manager: homeConfigurations/scott.nix
#             (shares the tailscale/git/tmux/util aliases, not the nix-*/idrive/temps ones)
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
        # (airbook has no sshd — see hosts/airbook-darwin/home.nix)
        nas01 = "tailscale ssh nas01";
        backup = "tailscale ssh nas01-backup";
        log01 = "tailscale ssh log01";
        pihole01 = "tailscale ssh pihole01";
        pihole02 = "tailscale ssh pihole02";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
        vm01 = "tailscale ssh vm01";
        otworkstation = "tailscale ssh OTworkstation";
        work-debian = "tailscale ssh sjensen@work-debian";

        # Tailscale troubleshooting
        ts-status = "tailscale status";
        ts-up = "sudo tailscale up";
        ts-down = "sudo tailscale down";
        ts-netcheck = "tailscale netcheck";
        ts-ip = "tailscale ip";
        ts-peers = "tailscale status --peers";
        ts-debug = "tailscale debug";
        # Enabled features for a node: no arg = self, or pass a hostname for a peer
        ts-info = ''f(){ if [ -z "$1" ]; then tailscale status --json | jq '.Self | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry, SSH: ((.Capabilities // []) | any(. == "https://tailscale.com/cap/ssh"))}'; else out=$(tailscale status --json | jq --arg h "$1" '.Peer[] | select((.HostName|ascii_downcase) == ($h|ascii_downcase)) | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry}'); if [ -z "$out" ]; then echo "ts-info: no peer matching '$1'" >&2; else echo "$out"; fi; fi; }; f'';

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
        nix-update = "nix flake update";

        # NixOS system shortcuts with automatic hostname detection
        nix-rebuild = "_d=$PWD; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd ~/git/nixos; GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git pull && sudo nixos-rebuild switch --flake ~/git/nixos#$(hostname); [ \"$_d\" != \"$HOME/git/nixos\" ] && cd -; unset _d; source ~/.bashrc";
        # nix-sync, fw-check, host-status: daily-driver only (modules/daily-driver.nix)

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Temperature monitoring
        temps = ''echo '=== CPU Temps (°F) ===' && sensors -f 2>/dev/null | grep -E ':.*°F' || echo '(run: sudo sensors-detect)'; echo ""; echo '=== Drive Temps (°F) ==='; for d in /dev/sd?; do C=$(sudo smartctl -A "$d" 2>/dev/null | awk '/^[[:space:]]*19[04] /{print $10}' | head -1); if [ -n "$C" ]; then printf "%s: %d°F\n" "$d" "$((C * 9 / 5 + 32))"; else printf "%s: N/A\n" "$d"; fi; done'';

        # Full SMART report: all drives by default, or one (e.g. `smart sda`)
        smart = ''f(){ if [ -n "$1" ]; then d="$1"; case "$d" in /dev/*) ;; *) d="/dev/$d";; esac; sudo smartctl -a "$d"; else for d in $(lsblk -dn -o NAME 2>/dev/null | grep -v '^loop'); do echo "=== /dev/$d ==="; sudo smartctl -a "/dev/$d"; echo; done; fi; }; f'';

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
