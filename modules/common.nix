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
        direnv
        jq
        tree
        vim
        tmux
        ncdu
        jdupes        # Deduplicate files

        # Development Tools
        git

        # Network & Diagnostic Tools
        bind          # dig, nslookup
        curl
        netcat        # nc
        nmap
        rsync
        tcpdump       # packet analyzer
        wget

        # System Monitoring
        htop
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
      # Note: starship is configured via home-manager in homeConfigurations/scott.nix
    };

    # Timezone
    time = {
      timeZone = "America/Chicago";
    };

    # Docker virtualization
    virtualisation.docker.enable = true;
  };
}
