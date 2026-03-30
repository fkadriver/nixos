{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules.tailscale
    inputs.self.nixosModules.shell-aliases
  ];
  config = {
    # Core system packages (server-safe, no GUI dependencies)
    environment = {
      systemPackages = with pkgs; [
        # CLI Utilities
        age           # Encryption tool for SOPS
        sops          # Secret operations (encryption, decryption, updatekeys)
        direnv
        jq
        tree
        vim
        tmux
        ncdu
        jdupes        # Deduplicate files
        ripgrep       # fast ripgrep

        # Development Tools
        gh            # GitHub CLI
        git

        # Disk Tools
        gptfdisk      # sgdisk — GPT partition manipulation

        # Network & Diagnostic Tools
        bind          # dig, nslookup
        curl
        netcat        # nc
        nmap
        rsync
        tcpdump       # packet analyzer
        wget
        minicom
        tio	      # minicom had issues with ttyUSB0 on latitude

        # System Monitoring
        htop
        btop
        lm_sensors    # CPU/board temp (sensors command)
        hddtemp       # Hard drive temperature

        # Logging
        rsyslog
      ];
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # Localization
    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocaleSettings = {
        LC_ADDRESS = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
      };
    };

    # Nix configuration
    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
      };
      # Garbage collection - keep 5-10 generations
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    # Keep only the last 10 generations in the boot menu
    boot.loader.systemd-boot.configurationLimit = 10;
    boot.loader.grub.configurationLimit = 10;

    # Programs
    programs = {
      direnv = {
        enable = true;
        loadInNixShell = true;
        nix-direnv = {
          enable = true;
        };
      };
      git = {
        enable = true;
        config = {
          user.name = "Scott Jensen";
          user.email = "fkadriver@gmail.com";
        };
      };
      tmux = {
        enable = true;
        clock24 = true;
        keyMode = "vi";
        terminal = "screen-256color";
        historyLimit = 10000;
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
      bash = {};
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
          "custom.tailscale" = {
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
          hostname = {
            ssh_only = false;
            format = "[@$hostname]($style) ";
            style = "bold green";
          };
          aws.disabled = true;
          azure.disabled = true;
          gcloud.disabled = true;
          line_break.disabled = false;
        };
      };
    };

    # Timezone
    time = {
      timeZone = "America/Chicago";
    };

    # Docker virtualization
    virtualisation.docker.enable = true;

    # Tailscale accepts OPNsense's subnet routes, which override direct VLAN
    # routing and break local LAN connectivity. These rules ensure local VLAN
    # traffic uses the direct interface, not Tailscale. Safe for all hosts —
    # if the host isn't on a subnet, main table has no route and falls through.
    # Covers all local VLANs: MGMT (.1), SERVERS (.10), WIFI (.11),
    #                          GUEST (.20), HOME_ASSIST (.21)
    networking.localCommands = ''
      ${pkgs.iproute2}/bin/ip rule add to 192.168.0.0/20 priority 100 table main 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule add to 192.168.16.0/20 priority 101 table main 2>/dev/null || true
    '';
  };
}
