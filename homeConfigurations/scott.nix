{ inputs, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    config = {
      home = {
        stateVersion = "25.05";
      };
      programs = {
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
              format = "[[TS:$output](bold green)] ";
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
