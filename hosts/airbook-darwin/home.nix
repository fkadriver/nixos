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
      claude-code  # Claude Code CLI

      # Utilities
      age
      htop
      sops
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
        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        # Darwin rebuild
        darwin-rebuild = "darwin-rebuild switch --flake ~/git/nixos#airbook-darwin";

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
        k = "kubectl";
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
        darwin-rebuild = "darwin-rebuild switch --flake ~/git/nixos#airbook-darwin";
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

    # VSCode extensions
    vscode = {
      enable = true;
      package = pkgs.vscode;
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
          conflicted = "=";
          ahead = "^$\{count}";
          behind = "v$\{count}";
          diverged = "^v^$\{ahead_count}v$\{behind_count}";
          untracked = "?$\{count}";
          stashed = "$";
          modified = "!$\{count}";
          staged = "+$\{count}";
          renamed = ">$\{count}";
          deleted = "x$\{count}";
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
          command = "tailscale status >/dev/null 2>&1 && echo 'ok' || echo 'x'";
          when = "command -v tailscale >/dev/null 2>&1";
          format = "[TS:$output](bold green) ";
          description = "Tailscale VPN status";
        };

        sudo = {
          disabled = false;
          symbol = "# ";
          style = "bold red";
        };

        cmd_duration = {
          min_time = 500;
          format = "took [$duration]($style) ";
          style = "bold yellow";
        };

        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[>](bold red)";
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
      };
    };
  };
}
