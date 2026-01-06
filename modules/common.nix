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
        direnv
        git
        htop
        jq
        tree
        vim
        wget
        curl
        rsync
        tmux
        ncdu
        # Network troubleshooting tools
        bind          # dig, nslookup
        netcat        # nc
        tcpdump       # packet analyzer
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
    };

    # Programs
    programs = {
      direnv = {
        enable = true;
        loadInNixShell = true;
        nix-direnv = {
          enable = true;
        };
      };
      starship = {
        enable = true;
        # Starship is a fast, customizable shell prompt
        # Config file can be created at ~/.config/starship.toml
      };
    };

    # Timezone
    time = {
      timeZone = "America/Chicago";
    };

    # Docker virtualization
    virtualisation.docker.enable = true;
  };
}
