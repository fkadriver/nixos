{ inputs, ... }@flakeContext:
let
  # Base module — applied on ALL hosts (nas01 standalone + NixOS desktops via nixosModule).
  # Must contain nothing nas01-specific (no Nix profile PATH, no borg server functions).
  baseModule = { config, lib, pkgs, ... }: {
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
            # Basic
            wtf = "alias";
            clr = "clear";
            urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
            urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

            # Docker one-liners
            cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

            # Tailscale SSH to other hosts
            airbook  = "tailscale ssh airbook";
            latitude = "tailscale ssh latitude";
            vm01     = "tailscale ssh vm01";
            pihole01 = "tailscale ssh pihole01";
            pihole02 = "tailscale ssh pihole02";
            log01    = "tailscale ssh sands-log01";

            # Tailscale troubleshooting
            ts-status   = "tailscale status";
            ts-up       = "sudo tailscale up";
            ts-down     = "sudo tailscale down";
            ts-netcheck = "tailscale netcheck";
            ts-ip       = "tailscale ip";
            ts-peers    = "tailscale status --peers";
            ts-self     = "tailscale status --self";
            ts-debug    = "tailscale debug";

            # Grep with color
            gpc = "grep --color=always";

            # Git shortcuts
            g   = "git";
            gs  = "git status";
            ga  = "git add";
            gaa = "git add -A";
            gc  = "git commit";
            gcm = "git commit -m";
            gp  = "git push";
            gpl = "git pull";
            gd  = "git diff";
            gdc = "git diff --cached";
            gl  = "git log --oneline --graph --decorate";
            gla = "git log --oneline --graph --decorate --all";
            gco = "git checkout";
            gb  = "git branch";
            gba = "git branch -a";
            gf  = "git fetch";
            gr  = "git restore";
            grs = "git restore --staged";

            # Tmux shortcuts
            t   = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
            tls = "tmux list-sessions";
            tn  = "tmux new-session -s";
            ta  = "tmux attach-session -t";
            tk  = "tmux kill-session -t";

            # Common utilities
            ll    = "ls -lah";
            la    = "ls -A";
            l     = "ls -CF";
            ".."  = "cd ..";
            "..." = "cd ../..";
            "...." = "cd ../../..";
          };
          # No initExtra here — differs between nas01 and NixOS hosts
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
            add_newline = true;
            format = lib.concatStrings [
              "$username"
              "$hostname"
              "$directory"
              "$git_branch"
              "$git_status"
              "$python"
              "$nix_shell"
              "$direnv"
              "$custom"
              "$sudo"
              "$cmd_duration"
              "$line_break"
              "$character"
            ];
            directory = {
              truncation_length = 3;
              truncate_to_repo = true;
              style = "bold cyan";
            };
            git_branch = {
              symbol = " ";
              style = "bold purple";
            };
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
            python = {
              symbol = " ";
              style = "yellow bold";
              pyenv_version_name = true;
            };
            nix_shell = {
              symbol = " ";
              format = "via [$symbol$state]($style) ";
              impure_msg = "";
              pure_msg = "pure";
            };
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
            custom.tailscale = {
              command = "tailscale status >/dev/null 2>&1 && echo '✓' || echo '✗'";
              when = "command -v tailscale >/dev/null 2>&1";
              format = "[TS:$output](bold green) ";
              description = "Tailscale VPN status";
            };
            sudo = {
              disabled = false;
              symbol = "🧙 ";
              style = "bold red";
            };
            cmd_duration = {
              min_time = 500;
              format = "took [$duration]($style) ";
              style = "bold yellow";
            };
            character = {
              success_symbol = "[➜](bold green)";
              error_symbol = "[➜](bold red)";
            };
            aws.disabled = true;
            azure.disabled = true;
            gcloud.disabled = true;
            line_break.disabled = false;
          };
        };
      };
    };
  };

  # nas01 standalone module — baseModule + nas01-specific additions.
  # NOT applied to NixOS hosts. Only used by home-manager switch on nas01.
  homeModule = { config, lib, pkgs, ... }: {
    imports = [ baseModule ];
    config = {
      programs.bash.shellAliases = {
        # nas01 deploy
        nix-apply  = "cd ~/git/nixos && git pull && sudo ./hosts/nas01/apply.sh; cd -; source ~/.bashrc";
        nix-update = "nix flake update";
        nix-search = "nix search nixpkgs";

        # Borg server overview (no passphrase needed — uses filesystem timestamps)
        borg-repos = ''echo "=== Borg Repos ===" && for repo in /mnt/wd18t_3/borg/repos/*/; do host=$(basename "$repo"); last=$(stat -c "%y" "''${repo}"index.* 2>/dev/null | sort | tail -1 | cut -d'.' -f1); size=$(du -sh "''${repo}" 2>/dev/null | cut -f1); printf "%-20s %-8s %s\n" "$host" "''${size:--}" "''${last:-no backups}"; done'';

        # ZFS status
        zs    = "zpool status";
        zsv   = "zpool status -v";
        zpl   = "zpool list";

        # ZFS list
        zl    = "zfs list";
        zla   = "zfs list -t all";
        zls   = "zfs list -t snapshot";
        zll   = "zfs list -o name,used,avail,refer,mountpoint";

        # ZFS create (compression=lz4 by default)
        zc    = "zfs create -o compression=lz4";

        # ZFS destroy
        zd    = "zfs destroy";
        zdr   = "zfs destroy -r";

        # Temperature monitoring
        temps = "echo '=== CPU Temps ===' && sensors 2>/dev/null || echo '(run: sudo sensors-detect)'; echo ''; echo '=== Drive Temps ===' && for d in /dev/sd?; do echo -n \"$d: \"; sudo hddtemp $d 2>/dev/null || sudo smartctl -A $d | grep -i 'temperature\\|194'; done";
      };
      programs.bash.initExtra = ''
        export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin:/nix/var/nix/profiles/nas01/bin"

        # Borg server functions — take hostname as argument
        # Usage: borg-ls latitude | borg-check vm01 | borg-unlock airbook-darwin
        BORG_BIN=/nix/var/nix/profiles/nas01/bin/borg
        BORG_REPOS=/mnt/wd18t_3/borg/repos
        borg-ls()     { sudo "$BORG_BIN" list      "$BORG_REPOS/$1"; }
        borg-check()  { sudo "$BORG_BIN" check     "$BORG_REPOS/$1"; }
        borg-unlock() { sudo "$BORG_BIN" break-lock "$BORG_REPOS/$1"; }
      '';
    };
  };

  # NixOS module — only baseModule, no nas01-specific PATH or borg functions.
  # Imported by desktop-minimal.nix for NixOS desktop hosts (latitude, etc.).
  nixosModule = { ... }: {
    home-manager.users.scott = baseModule;
  };
in
(
  (
    inputs.home-manager.lib.homeManagerConfiguration {
      modules = [ homeModule ];
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    }
  ) // { inherit nixosModule; }
)
