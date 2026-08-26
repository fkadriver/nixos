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
      # # Input Leap server layout: airbook.local is to the left of latitude
      # xdg.configFile."InputLeap/input-leap.conf".text = ''
      #   section: screens
      #     latitude:
      #     airbook.local:
      #   end

      #   section: links
      #     latitude:
      #       left = airbook.local
      #     airbook.local:
      #       right = latitude
      #   end

      #   section: options
      #   end
      # '';

      # # Input Leap GUI settings: point to the external config file above
      # # useExternalConfig=true so the GUI uses input-leap.conf instead of its internal grid
      # xdg.configFile."InputLeap/InputLeap.conf".force = true;
      # xdg.configFile."InputLeap/InputLeap.conf".text = ''
      #   [General]
      #   autoHide=false
      #   autoStart=false
      #   configFile=/home/scott/.config/InputLeap/input-leap.conf
      #   cryptoEnabled=true
      #   elevateMode=false
      #   elevateModeEnum=0
      #   groupClientChecked=false
      #   groupServerChecked=true
      #   interface=
      #   language=en
      #   logFilename=/var/log/input-leap.log
      #   logLevel=3
      #   logToFile=false
      #   minimizeToTray=false
      #   port=24800
      #   requireClientCertificate=false
      #   screenName=latitude
      #   serverHostname=
      #   startedBefore=true
      #   useExternalConfig=true
      #   useInternalConfig=false
      #   wizardLastRun=9
      # '';

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
            # (airbook has no sshd — see hosts/airbook-darwin/home.nix)
            latitude = "tailscale ssh latitude";
            backup   = "tailscale ssh nas01-backup";
            vm01     = "tailscale ssh vm01";
            pihole01 = "tailscale ssh pihole01";
            pihole02 = "tailscale ssh pihole02";
            log01    = "tailscale ssh log01";
            otworkstation = "tailscale ssh OTworkstation";
            ot       = "tailscale ssh OTworkstation";

            # Tailscale troubleshooting
            ts-status   = "tailscale status";
            ts-up       = "sudo tailscale up";
            ts-down     = "sudo tailscale down";
            ts-netcheck = "tailscale netcheck";
            ts-ip       = "tailscale ip";
            ts-peers    = "tailscale status --peers";
            ts-debug    = "tailscale debug";
            # Enabled features for a node: no arg = self, or pass a hostname for a peer
            ts-info = ''f(){ if [ -z "$1" ]; then tailscale status --json | jq '.Self | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry, SSH: ((.Capabilities // []) | any(. == "https://tailscale.com/cap/ssh"))}'; else out=$(tailscale status --json | jq --arg h "$1" '.Peer[] | select((.HostName|ascii_downcase) == ($h|ascii_downcase)) | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry}'); if [ -z "$out" ]; then echo "ts-info: no peer matching '$1'" >&2; else echo "$out"; fi; fi; }; f'';

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

  # NixOS module — imported by NixOS hosts via home-manager.
  # (nas01-specific server aliases live in hosts/nas01/default.nix since the
  # Ubuntu-era standalone home-manager setup was retired.)
  nixosModule = { ... }: {
    home-manager.users.scott = baseModule;
  };
in
(
  (
    inputs.home-manager.lib.homeManagerConfiguration {
      modules = [ baseModule ];
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    }
  ) // { inherit nixosModule; }
)
