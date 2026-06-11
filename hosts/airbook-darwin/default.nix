{ inputs, ... }@flakeContext:
let
  system = "x86_64-darwin";  # MacBook Air 7,2 is Intel
  pkgs = inputs.nixpkgs.legacyPackages.${system};

  bosl2 = pkgs.fetchFromGitHub {
    owner = "BelfrySCAD";
    repo = "BOSL2";
    rev = "881947c32a28fa68049b518dcc1e73202bfc2c7c";
    hash = "sha256-0qy9WX7lhiVoY5Jv5pdXHOMXf6QfnrEJ5XHzv5B2Skk=";
  };

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
      python3
      claude-code

      # Input Leap: KVM client — connects to latitude's keyboard/mouse server
      input-leap

      # Backup
      borgbackup

    ];

    # Craft / decorative fonts (matches craftFonts in font.nix)
    fonts.packages =
      let
        great-vibes = pkgs.stdenvNoCC.mkDerivation {
          name = "great-vibes";
          src = pkgs.fetchurl {
            url = "https://github.com/google/fonts/raw/main/ofl/greatvibes/GreatVibes-Regular.ttf";
            sha256 = "059dk3wnfi5kr7q97jpszmdrm3q9x09z7v1i4mbm26vg3019hl4d";
          };
          dontUnpack = true;
          installPhase = "install -Dm644 $src $out/share/fonts/truetype/GreatVibes-Regular.ttf";
        };
        allura = pkgs.stdenvNoCC.mkDerivation {
          name = "allura";
          src = pkgs.fetchurl {
            url = "https://github.com/google/fonts/raw/main/ofl/allura/Allura-Regular.ttf";
            sha256 = "1ijcq6x62iiwnbi74ywkpx1ljca0iyhqx2zzqkgw0cjqa4p2n54w";
          };
          dontUnpack = true;
          installPhase = "install -Dm644 $src $out/share/fonts/truetype/Allura-Regular.ttf";
        };
        parisienne = pkgs.stdenvNoCC.mkDerivation {
          name = "parisienne";
          src = pkgs.fetchurl {
            url = "https://github.com/google/fonts/raw/main/ofl/parisienne/Parisienne-Regular.ttf";
            sha256 = "0mydmb3lxjn1qp4ydncq1jpl7yjbs5bzbrcp0xqbq81f09zy37mw";
          };
          dontUnpack = true;
          installPhase = "install -Dm644 $src $out/share/fonts/truetype/Parisienne-Regular.ttf";
        };
        fleur-de-lis-font = pkgs.stdenvNoCC.mkDerivation {
          name = "fleur-de-lis-font";
          src = pkgs.fetchurl {
            url = "https://dl.dafont.com/dl/?f=fleur_de_lis";
            sha256 = "1kh540jyxsy81651zl5zyq06p7nwkn3s75l9z95gqgjmydkl9hiq";
          };
          nativeBuildInputs = [ pkgs.unzip ];
          unpackPhase = "unzip $src";
          installPhase = ''install -Dm644 "Fleur de Lis.ttf" "$out/share/fonts/truetype/FleurDeLis.ttf"'';
        };
        # nymphette = pkgs.stdenvNoCC.mkDerivation {
        #   name = "nymphette";
        #   src = pkgs.fetchurl {
        #     url = "https://www.fontsquirrel.com/fonts/download/nymphette";
        #     sha256 = "1mr05s0zhnqbgq6jljwnbj3zygnv33lj5aq5rrapvxw78bzjzlyr";
        #   };
        #   nativeBuildInputs = [ pkgs.unzip ];
        #   unpackPhase = "unzip $src";
        #   installPhase = ''install -Dm644 "Nymphette.ttf" "$out/share/fonts/truetype/Nymphette.ttf"'';
        # };
      in
        [ great-vibes allura parisienne fleur-de-lis-font ]
        ++ (if pkgs ? "eb-garamond"       then [ pkgs."eb-garamond" ]       else [])
        ++ (if pkgs ? "libre-baskerville" then [ pkgs."libre-baskerville" ] else [])
        ++ (if pkgs ? "oldstandard"       then [ pkgs."oldstandard" ]       else [])
        ++ (if pkgs ? "junicode"          then [ pkgs."junicode" ]          else [])
        ++ (if pkgs ? "symbola"           then [ pkgs."symbola" ]           else []);

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
        "bitwarden-cli"  # nix version requires xcodebuild, use homebrew instead
        "duti"           # Set default file type associations on macOS
      ];
      casks = [
        "balenaetcher"       # USB image writer
        "bitwarden"
        "firefox"
        "iterm2"
        "rectangle"          # Window management
        "scroll-reverser"    # Natural scroll for trackpad, reversed for mouse
        "visual-studio-code"

        # 3D printing and modeling (from 3d-printing.nix)
        "openscad@snapshot"
        "orcaslicer"
        "prusaslicer"
        "freecad"
        "blender"
        "meshlab"
        "inkscape"
        "gimp"

        # Gaming (from daily-driver.nix)
        "heroic"           # Epic, GOG, Amazon Prime games launcher

        # Video transcoding
        "handbrake-app"

        # Office and productivity
        "libreoffice"
        "thunderbird"

        # 2D CAD
        "librecad"
        "qcad"

        # Text editor
        "geany"

        # Utilities
        "tailscale-app"    # VPN with tray icon (replaces nix-darwin service; renamed from tailscale)
        "caffeine"         # Prevent Mac from sleeping (menubar app)
        "rustdesk"         # Remote desktop to latitude (via Tailscale)
        "sweet-home3d"     # Interior design and home planning
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

        # Software Update - Prevent automatic upgrades (important for OCLP)
        # This prevents macOS from auto-upgrading to Tahoe while on Sequoia
        SoftwareUpdate = {
          AutomaticallyInstallMacOSUpdates = false;
        };

        # Additional Software Update controls via CustomUserPreferences
        CustomUserPreferences = {
          "com.apple.SoftwareUpdate" = {
            AutomaticCheckEnabled = true;      # Still check for updates (to see security patches)
            AutomaticDownload = false;         # Don't auto-download updates
            AutomaticallyInstallMacOSUpdates = false;  # Don't auto-install macOS updates
            CriticalUpdateInstall = false;     # Don't auto-install even "critical" updates
          };
          "com.apple.commerce" = {
            AutoUpdate = false;                # Don't auto-update App Store apps
          };
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
    sops = {
      defaultSopsFile = ../../secrets/secrets.yaml;
      age.keyFile = "/var/root/.config/sops/age/keys.txt";

      secrets = {
        # SSH keys deployed via sops-nix
        "ssh/id_ed25519" = {
          path = "/Users/scott/.ssh/id_ed25519";
          mode = "0600";
          owner = "scott";
        };
        "ssh/id_ed25519.pub" = {
          path = "/Users/scott/.ssh/id_ed25519.pub";
          mode = "0644";
          owner = "scott";
        };
        "ssh/id_ed25519_github" = {
          path = "/Users/scott/.ssh/id_ed25519_github";
          mode = "0600";
          owner = "scott";
        };
        "ssh/id_ed25519_github.pub" = {
          path = "/Users/scott/.ssh/id_ed25519_github.pub";
          mode = "0644";
          owner = "scott";
        };
        "ssh/id_ed25519_legacy" = {
          path = "/Users/scott/.ssh/id_ed25519_legacy";
          mode = "0600";
          owner = "scott";
        };
        "ssh/id_ed25519_legacy.pub" = {
          path = "/Users/scott/.ssh/id_ed25519_legacy.pub";
          mode = "0644";
          owner = "scott";
        };
        "ssh/opnsense_admin_ed25519" = {
          path = "/Users/scott/.ssh/opnsense_admin_ed25519";
          mode = "0600";
          owner = "scott";
        };
        "ssh/opnsense_admin_ed25519.pub" = {
          path = "/Users/scott/.ssh/opnsense_admin_ed25519.pub";
          mode = "0644";
          owner = "scott";
        };

        # Bitwarden credentials (for fetching borg passphrase at backup time)
        "bitwarden/client_id" = {
          path = "/Users/scott/.local/share/bitwarden-secrets/client_id";
          mode = "0400";
          owner = "scott";
        };
        "bitwarden/client_secret" = {
          path = "/Users/scott/.local/share/bitwarden-secrets/client_secret";
          mode = "0400";
          owner = "scott";
        };
        "bitwarden/master_password" = {
          path = "/Users/scott/.local/share/bitwarden-secrets/master_password";
          mode = "0400";
          owner = "scott";
        };
      };
    };

    # Install BOSL2 library to OpenSCAD user libraries directory
    system.activationScripts.openscadBosl2.text = ''
      OPENSCAD_LIB="/Users/scott/Library/Application Support/OpenSCAD/libraries"
      mkdir -p "$OPENSCAD_LIB"
      if [ ! -L "$OPENSCAD_LIB/BOSL2" ]; then
        rm -rf "$OPENSCAD_LIB/BOSL2"
        ln -sfn ${bosl2} "$OPENSCAD_LIB/BOSL2"
        chown -h scott:staff "$OPENSCAD_LIB/BOSL2" 2>/dev/null || true
      fi
    '';

    # Fix ownership of sops-created directories (sops runs as root and creates parent dirs as root)
    system.activationScripts.fixSopsOwnership.text = ''
      chown scott:staff /Users/scott/.local/share || true
      chown scott:staff /Users/scott/.local/share/bitwarden-secrets || true
    '';

    # Borg backup to nas01 via launchd (macOS equivalent of systemd)
    launchd.daemons.borg-backup =
      let
        borgScript = pkgs.writeShellScript "borg-backup" ''
          set -euo pipefail

          BW_SECRETS="/Users/scott/.local/share/bitwarden-secrets"
          REPO="ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18t_3/borg/repos/airbook-darwin"
          # Borg passphrase: Bitwarden item 91db7811-ddf1-49aa-8a42-b3d60188a6e6 (Borg Encryption)
          BW_BORG_ITEM_ID="91db7811-ddf1-49aa-8a42-b3d60188a6e6"

          export BW_CLIENTID="$(cat "$BW_SECRETS/client_id")"
          export BW_CLIENTSECRET="$(cat "$BW_SECRETS/client_secret")"
          export BW_PASSWORD="$(cat "$BW_SECRETS/master_password")"
          export HOME="/Users/scott"

          echo "=== Borg backup started: $(date) ==="

          # Authenticate to Bitwarden and fetch passphrase
          BW="/usr/local/bin/bw"
          "$BW" login --apikey --quiet 2>/dev/null || true
          BW_SESSION="$("$BW" unlock --passwordenv BW_PASSWORD --raw)"
          export BORG_PASSPHRASE="$("$BW" get item "$BW_BORG_ITEM_ID" \
            | ${pkgs.jq}/bin/jq -r '.login.password' )"
          "$BW" lock --quiet || true

          export BORG_RSH="${pkgs.openssh}/bin/ssh -i /Users/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new"
          export BORG_REMOTE_PATH="/nix/var/nix/profiles/nas01/bin/borg"

          ${pkgs.borgbackup}/bin/borg create \
            --stats \
            --compression auto,zstd \
            --exclude-caches \
            --exclude "*/node_modules" \
            --exclude "*/.npm" \
            --exclude "*/.cargo" \
            --exclude "*/.rustup" \
            --exclude "*/.cache" \
            --exclude "*/Cache" \
            --exclude "*/Library/Caches" \
            --exclude "*/Library/Application Support/*/Cache" \
            --exclude "*.pyc" \
            --exclude "*/__pycache__" \
            "''${REPO}::airbook-darwin-$(date +%Y-%m-%dT%H:%M:%S)" \
            /Users/scott

          ${pkgs.borgbackup}/bin/borg prune \
            --keep-daily 7 \
            --keep-weekly 4 \
            --keep-monthly 6 \
            "$REPO"

          echo "=== Borg backup complete: $(date) ==="
        '';
      in {
        serviceConfig = {
          Label = "com.local.borg-backup";
          ProgramArguments = [ "${borgScript}" ];
          StartCalendarInterval = [{ Hour = 2; Minute = 0; }];
          UserName = "scott";
          RunAtLoad = false;
          StandardOutPath = "/Users/scott/.local/share/borg/backup.log";
          StandardErrorPath = "/Users/scott/.local/share/borg/backup.error.log";
        };
      };

    # Enable SSH server (Remote Login)
    system.activationScripts.remoteLogin.text = ''
      /usr/sbin/systemsetup -setremotelogin on > /dev/null 2>&1 || true
    '';

    # Services
    services = {
      # Syncthing file synchronization
      # Note: Syncthing is installed via Homebrew brew above
      # The GUI will be available at http://127.0.0.1:8384
      # Configuration is managed through the GUI or config file
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
