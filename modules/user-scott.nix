{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    users = {
      users = {
        scott = {
          extraGroups = [
            "docker"
            "networkmanager"
            "wheel"
            "plugdev"  # For iPhone/iOS device access
          ];
          hashedPassword = "$y$j9T$PwV0AT33FffSLHl9QH6Uf.$bVwBG9Vy5wH9k0QW7V4fawCa68eCtpCpAOKals3vOF0";
          isNormalUser = true;
        };
      };
    };

    # Passwordless sudo for tailscale commands
    security.sudo.extraRules = [
      {
        users = [ "scott" ];
        commands = [
          {
            command = "/nix/store/*/bin/tailscale *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/tailscale *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # SSH configuration (agent started by desktop environment)
    programs.ssh = {
      extraConfig = ''
        # Automatically add keys to agent when first used
        AddKeysToAgent yes

        # Default identity files (loaded in order)
        IdentityFile ~/.ssh/id_ed25519
        IdentityFile ~/.ssh/id_ed25519_legacy

        # GitHub
        Host github.com
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes

        # Legacy systems
        Host *.local 192.168.*.*
          IdentityFile ~/.ssh/id_ed25519_legacy
          IdentitiesOnly yes
      '';
    };

    # Git configuration for user scott
    programs.git = {
      enable = true;
      config = {
        user = {
          name = "Scott Jensen";
          email = "fkadriver@gmail.com";
        };
        init = {
          defaultBranch = "main";
        };
        pull = {
          rebase = false;  # Use merge strategy (can change to true for rebase)
        };
        push = {
          autoSetupRemote = true;  # Automatically set up tracking for new branches
        };
        core = {
          editor = "vim";
        };
        # Helpful aliases built into git config
        alias = {
          st = "status";
          co = "checkout";
          br = "branch";
          ci = "commit";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          lg = "log --graph --oneline --decorate --all";
        };
      };
    };

    # Starship prompt configuration for user scott
    programs.starship = {
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
      };
    };
  };
}
