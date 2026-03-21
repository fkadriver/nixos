{ inputs, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    imports = [ ../home-modules/freecad.nix ];
    config = {
      home = {
        username = "scott";
        homeDirectory = "/home/scott";
        stateVersion = "25.11";
        # Add ~/.local/bin to PATH for non-interactive shells (VS Code Server)
        sessionPath = [ "$HOME/.local/bin" ];
      };
      programs = {
        bash = {
          enable = true;
          historySize = 10000;
          historyFileSize = 100000;
          historyControl = [ "ignoredups" "ignorespace" ];
          shellOptions = [
            "histappend"
            "checkwinsize"
            "extglob"
            "globstar"
            "checkjobs"
          ];
          shellAliases = {
            k = "kubectl";
            urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
            urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

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
            nix-apply = "cd ~/git/nixos && git pull && sudo ./hosts/nas01/apply.sh";
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
            borg-list   = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg borg list ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)'';
            borg-info   = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg borg info ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)'';
            borg-check  = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg borg check ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)'';
            borg-unlock = ''sudo env BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg borg break-lock ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)'';

            # Common utilities
            ll = "ls -lah";
            la = "ls -A";
            l = "ls -CF";
            ".." = "cd ..";
            "..." = "cd ../..";
            "...." = "cd ../../..";
          };
          initExtra = ''
            export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin:/nix/var/nix/profiles/nas01/bin"
          '';
        };
        direnv = {
          enable = true;
          enableBashIntegration = true;
        };
        jq = {
          enable = true;
        };
        starship = {
          enable = true;
          settings = {
            # Add a newline before each prompt
            add_newline = true;

            # Format: customize what shows in the prompt
            format = lib.concatStrings [
              "$username"
              "$hostname"
              "$directory"
              "$git_branch"
              "$git_status"
              "$python"
              "$nix_shell"
              "$direnv"
              "$custom"  # Custom modules (Tailscale, etc.)
              "$sudo"
              "$cmd_duration"
              "$line_break"
              "$character"
            ];

            # Directory settings
            directory = {
              truncation_length = 3;
              truncate_to_repo = true;
              style = "bold cyan";
            };

            # Git branch
            git_branch = {
              symbol = " ";
              style = "bold purple";
            };

            # Git status
            git_status = {
              conflicted = "🏳";
              ahead = "⇡\${count}";
              behind = "⇣\${count}";
              diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
              untracked = "?\${count}";
              stashed = "$";
              modified = "!\${count}";
              staged = "+\${count}";
              renamed = "»\${count}";
              deleted = "✘\${count}";
              style = "bold red";
            };

            # Python version
            python = {
              symbol = " ";
              style = "yellow bold";
              pyenv_version_name = true;
            };

            # Nix shell indicator
            nix_shell = {
              symbol = " ";
              format = "via [$symbol$state]($style) ";
              impure_msg = "";
              pure_msg = "pure";
            };

            # direnv status
            direnv = {
              disabled = false;
              format = "[$symbol$loaded/$allowed]($style) ";
              symbol = "direnv ";
              style = "bold orange";
              allowed_msg = "allowed";
              denied_msg = "denied";
              loaded_msg = "loaded";
              unloaded_msg = "unloaded";
            };

            # Custom modules
            custom.tailscale = {
              command = "tailscale status >/dev/null 2>&1 && echo '✓' || echo '✗'";
              when = "command -v tailscale >/dev/null 2>&1";
              format = "[TS:$output](bold green) ";
              description = "Tailscale VPN status";
            };

            # Sudo indicator
            sudo = {
              disabled = false;
              symbol = "🧙 ";
              style = "bold red";
            };

            # Command duration
            cmd_duration = {
              min_time = 500;
              format = "took [$duration]($style) ";
              style = "bold yellow";
            };

            # Prompt character
            character = {
              success_symbol = "[➜](bold green)";
              error_symbol = "[➜](bold red)";
            };

            # Disable cloud provider modules (not used from CLI)
            aws.disabled = true;
            azure.disabled = true;
            gcloud.disabled = true;
            line_break.disabled = false;
          };
        };
      };
    };
  };
  nixosModule = { ... }: {
    home-manager.users.scott = homeModule;
  };
in
(
  (
    inputs.home-manager.lib.homeManagerConfiguration {
      modules = [
        homeModule
      ];
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    }
  ) // { inherit nixosModule; }
)
