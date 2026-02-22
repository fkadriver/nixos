{ inputs, ... }@flakeContext:
let
  system = "x86_64-darwin";  # MacBook Air 7,2 is Intel
  pkgs = inputs.nixpkgs.legacyPackages.${system};

  darwinModule = { config, lib, pkgs, ... }: {
    # Nix configuration
    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "root" "scott" ];
      };
      # Garbage collection
      gc = {
        automatic = true;
        interval = { Weekday = 0; Hour = 2; Minute = 0; };
        options = "--delete-older-than 30d";
      };
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # System packages (CLI tools)
    environment.systemPackages = with pkgs; [
      # Essential CLI tools
      bat
      btop
      curl
      direnv
      fd
      fzf
      git
      jq
      neovim
      ripgrep
      tmux
      tree
      unzip
      wget
      yq-go
      zip

      # Development
      gh
      gnumake

      # Networking
      tailscale
    ];

    # Homebrew for GUI apps and casks
    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "zap";  # Remove unlisted packages
        upgrade = true;
      };
      brews = [
        "syncthing"
      ];
      casks = [
        "bitwarden"
        "firefox"
        "iterm2"
        "rectangle"      # Window management
        "visual-studio-code"
      ];
    };

    # macOS system settings
    system = {
      defaults = {
        # Dock settings
        dock = {
          autohide = true;
          autohide-delay = 0.0;
          autohide-time-modifier = 0.2;
          minimize-to-application = true;
          mru-spaces = false;  # Don't rearrange spaces based on recent use
          orientation = "bottom";
          show-recents = false;
          tilesize = 48;
        };

        # Finder settings
        finder = {
          AppleShowAllExtensions = true;
          AppleShowAllFiles = false;
          FXDefaultSearchScope = "SCcf";  # Current folder
          FXEnableExtensionChangeWarning = false;
          FXPreferredViewStyle = "clmv";  # Column view
          QuitMenuItem = true;
          ShowPathbar = true;
          ShowStatusBar = true;
        };

        # Global settings
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";  # Dark mode
          AppleKeyboardUIMode = 3;       # Full keyboard access
          ApplePressAndHoldEnabled = false;  # Key repeat instead of character picker
          InitialKeyRepeat = 15;
          KeyRepeat = 2;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false;
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticSpellingCorrectionEnabled = false;
        };

        # Trackpad
        trackpad = {
          Clicking = true;  # Tap to click
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = true;
        };

        # Login window
        loginwindow = {
          GuestEnabled = false;
        };
      };

      # Keyboard shortcuts
      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToControl = true;
      };

      # Set macOS version (required for darwin-rebuild)
      stateVersion = 5;
    };

    # Enable Touch ID for sudo
    security.pam.services.sudo_local.touchIdAuth = true;

    # sops-nix for secrets management
    # Note: SSH keys are manually managed on macOS (already installed)
    # The bitwarden.nix module pattern used on NixOS doesn't work on darwin
    sops = {
      defaultSopsFile = ../../secrets/secrets.yaml;
      age.keyFile = "/var/root/.config/sops/age/keys.txt";

      # Secrets like Tailscale auth keys, WiFi passwords, etc. can be added here
      # SSH keys are already manually installed in ~/.ssh
      secrets = {
        # Example for future use:
        # "tailscale_auth_key" = {
        #   path = "/var/root/tailscale_auth_key";
        #   mode = "0400";
        # };
      };
    };

    # Services
    services = {
      # Tailscale VPN
      tailscale.enable = true;
    };

    # Create /etc/zshrc that loads nix-darwin environment
    programs.zsh.enable = true;
    programs.bash.enable = true;

    # Home Manager integration
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.scott = import ./home.nix;
    };

    # Set primary user for system defaults
    system.primaryUser = "scott";

    # User configuration
    users.users.scott = {
      name = "scott";
      home = "/Users/scott";
    };
  };
in
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit inputs; };
  modules = [
    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.darwinModules.sops
    darwinModule
  ];
}
