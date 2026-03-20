{ config, lib, pkgs, ... }:
let
  # Fetches the borg passphrase from Bitwarden using stored API credentials
  borgPassCmd = pkgs.writeShellScript "borg-getpass" ''
    export BW_CLIENTID="$(cat "$HOME/.local/share/bitwarden-secrets/client_id")"
    export BW_CLIENTSECRET="$(cat "$HOME/.local/share/bitwarden-secrets/client_secret")"
    export BW_PASSWORD="$(cat "$HOME/.local/share/bitwarden-secrets/master_password")"
    /usr/local/bin/bw login --apikey --quiet 2>/dev/null || true
    export BW_SESSION="$(/usr/local/bin/bw unlock --passwordenv BW_PASSWORD --raw)"
    /usr/local/bin/bw get item "91db7811-ddf1-49aa-8a42-b3d60188a6e6" \
      | ${pkgs.jq}/bin/jq -r '.login.password'
  '';
  borgRepo = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/airbook-darwin";
  borgEnv  = ''BORG_RSH="ssh -i $HOME/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="${borgPassCmd}" BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg'';
in
{
  imports = [ ../../home-modules/freecad.nix ];

  home = {
    username = "scott";
    homeDirectory = "/Users/scott";
    stateVersion = "24.11";

    # Add ~/.local/bin to PATH
    sessionPath = [ "$HOME/.local/bin" "$HOME/go/bin" ];

    # User packages (in addition to system packages)
    packages = with pkgs; [
      # Development
      go
      nodejs
      python3
      # claude-code  # Disabled: build fails on macOS (npm dependency issues)

      # Nix development tools (for VS Code Nix IDE)
      nil            # Nix language server
      nixpkgs-fmt    # Nix formatter

      # Utilities
      age
      htop
      sops

      # 3D printing fonts (from 3d-printing.nix)
      eb-garamond
      libre-baskerville
      oldstandard
      junicode
      inter
      source-sans
    ];
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
        # Basic (from shell-aliases.nix)
        wtf = "alias";
        clr = "clear";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        log01 = "tailscale ssh sands-log01";
        pi-hole = "tailscale ssh pi-hole";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
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

        # Common utilities
        ll = "ls -lah";
        la = "ls -A";
        l = "ls -CF";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Borg backup (darwin - uses launchd instead of systemd)
        borg-status = "sudo launchctl list com.local.borg-backup";
        borg-logs   = "tail -100 $HOME/.local/share/borg/backup.log";
        borg-run    = "sudo launchctl start com.local.borg-backup";
        borg-list   = "env ${borgEnv} borg list ${borgRepo}";
        borg-info   = "env ${borgEnv} borg info ${borgRepo}";
        borg-check  = "env ${borgEnv} borg check ${borgRepo}";
        borg-unlock = "env ${borgEnv} borg break-lock ${borgRepo}";

        # System rebuild (darwin-specific)
        rebuild = "sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin";

        # macOS-specific
        flush-dns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      };
      initExtra = ''
        export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"

        # Source nix-darwin environment if present
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
      '';
    };

    zsh = {
      enable = true;
      history.size = 10000;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        # Basic (from shell-aliases.nix)
        wtf = "alias";
        clr = "clear";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        log01 = "tailscale ssh sands-log01";
        pi-hole = "tailscale ssh pi-hole";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
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

        # Common utilities
        ll = "ls -lah";
        la = "ls -A";
        l = "ls -CF";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Borg backup (darwin - uses launchd instead of systemd)
        borg-status = "sudo launchctl list com.local.borg-backup";
        borg-logs   = "tail -100 $HOME/.local/share/borg/backup.log";
        borg-run    = "sudo launchctl start com.local.borg-backup";
        borg-list   = "env ${borgEnv} borg list ${borgRepo}";
        borg-info   = "env ${borgEnv} borg info ${borgRepo}";
        borg-check  = "env ${borgEnv} borg check ${borgRepo}";
        borg-unlock = "env ${borgEnv} borg break-lock ${borgRepo}";

        # System rebuild (darwin-specific)
        rebuild = "sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin";

        # macOS-specific
        flush-dns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      };
      initContent = ''
        export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      '';
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "Scott";
          email = "scott@example.com";  # Update with your email
        };
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
      };
    };

    jq.enable = true;

    # VSCode - plain install, extensions managed via Settings Sync (GitHub account)
    # This allows installing any marketplace extension without Nix store limitations
    vscode = {
      enable = true;
      package = pkgs.vscode;
      # Extensions are installed via VS Code marketplace and synced via GitHub Settings Sync
      # Recommended extensions to install manually:
      # - jnoortheen.nix-ide           # Nix language support
      # - ms-python.python             # Python support
      # - ms-python.vscode-pylance     # Python IntelliSense
      # - eamodio.gitlens             # Git lens
      # - github.github-vscode-theme  # GitHub theme
      # - esbenp.prettier-vscode      # Prettier formatter
      # - anthropic.claude-code       # Claude Code AI assistant
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
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
          ignore_timeout = true;
        };

        sudo = {
          # Disabled on macOS: checking sudo credential cache via /usr/bin/sudo is slow
          disabled = true;
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

    tmux = {
      enable = true;
      terminal = "screen-256color";
      historyLimit = 10000;
      keyMode = "vi";
      clock24 = true;
      extraConfig = ''
        # Enable mouse support
        set -g mouse on

        # Start windows and panes at 1, not 0
        set -g base-index 1
        setw -g pane-base-index 1

        # Renumber windows when one is closed
        set -g renumber-windows on

        # Better colors
        set -g default-terminal "screen-256color"
        set -ga terminal-overrides ",*256col*:Tc"

        # Status bar styling
        set -g status-style 'bg=#333333 fg=#ffffff'
        set -g status-left-length 40
        set -g status-right '%H:%M %d-%b-%y'

        # Easy splits with | and -
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"

        # Vim-style pane navigation
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
      '';
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;  # Disable default config to avoid warnings
      matchBlocks = {
        "*" = {
          addKeysToAgent = "yes";
          identityFile = "~/.ssh/id_ed25519";
        };
        "nas01" = {
          hostname = "nas01.warthog-royal.ts.net";
          user = "scott";
        };
        "latitude" = {
          hostname = "latitude.warthog-royal.ts.net";
          user = "scott";
        };
        "github.com" = {
          hostname = "github.com";
          user = "git";
          identityFile = "~/.ssh/id_ed25519_github";
        };
      };
    };
  };
}
