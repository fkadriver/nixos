{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
# MAINTENANCE: When updating aliases here, also update:
#   - nas01: ~/.bash_aliases  (Ubuntu server, not Nix-managed)
#             deploy via: tailscale ssh scott@nas01
#   - Darwin: hosts/airbook-darwin/home.nix
#             (programs.bash.shellAliases / programs.zsh.shellAliases)
{
  config = {
    environment = {
      shellAliases = {
        # Basic
        wtf = "alias";
        clr = "clear";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        airbook = "tailscale ssh airbook";
        nas01 = "tailscale ssh nas01";
        log01 = "tailscale ssh sands-log01";
        pihole01 = "tailscale ssh pihole01";
        pihole02 = "tailscale ssh pihole02";
        prodesk = "tailscale ssh prodesk";
        slap = "tailscale ssh latitude";
        vm01 = "tailscale ssh vm01";

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
        nix-build-test = "nix flake check";
        nix-update = "nix flake update";
        nix-search = "nix search nixpkgs";
        nix-shell-python = "nix-shell -p python3 python3Packages.pip";

        # NixOS system shortcuts with automatic hostname detection
        rebuild = "sudo nixos-rebuild switch --flake .#$(hostname)";
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

        # Borg backup - service management
        borg-status = "sudo systemctl status borgbackup-job-system.service";
        borg-logs   = "sudo journalctl -u borgbackup-job-system.service -n 50";
        borg-timer  = "systemctl list-timers | grep borg";
        borg-run    = "sudo systemctl start borgbackup-job-system.service";

        # Borg backup - repository operations (passphrase from bitwarden, legacy SSH key)
        borg-list   = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/usr/bin/borg borg list ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)'';
        borg-info   = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/usr/bin/borg borg info ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)'';
        borg-check  = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/usr/bin/borg borg check ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)'';
        borg-unlock = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/usr/bin/borg borg break-lock ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)'';

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
