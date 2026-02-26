{ config, lib, pkgs, ... }: {
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
        prodesk = "tailscale ssh prodesk";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";

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
        prodesk = "tailscale ssh prodesk";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";

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

    # VSCode extensions (using new profile format)
    vscode = {
      enable = true;
      package = pkgs.vscode;
      profiles.default = {
        extensions = with pkgs.vscode-extensions; [
        # Claude Code (AI coding assistant)
        # Note: May need to be installed manually if not available in nixpkgs
        # anthropic.claude-code

        # Nix language support
        bbenoist.nix
        jnoortheen.nix-ide

        # Python
        ms-python.python
        ms-python.vscode-pylance

        # Git
        eamodio.gitlens

        # Themes
        github.github-vscode-theme

        # Other useful extensions
        esbenp.prettier-vscode
        yzhang.markdown-all-in-one
        ];
        userSettings = {
          "editor.fontSize" = 14;
          "editor.tabSize" = 2;
          "editor.formatOnSave" = true;
          "files.autoSave" = "afterDelay";
          "workbench.colorTheme" = "GitHub Dark Default";
          "git.autofetch" = true;
          "terminal.integrated.fontSize" = 13;
        };
      };
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

    tmux = {
      enable = true;
      terminal = "screen-256color";
      historyLimit = 10000;
      keyMode = "vi";
      extraConfig = ''
        # Enable mouse support
        set -g mouse on

        # Start windows and panes at 1, not 0
        set -g base-index 1
        setw -g pane-base-index 1

        # Renumber windows when one is closed
        set -g renumber-windows on
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
