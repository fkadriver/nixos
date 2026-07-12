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

  wazuhVersion = "4.14.5";

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
        cleanup = "none";
        upgrade = true;
      };
      brews = [
        "syncthing"
        "bitwarden-cli"  # nix version requires xcodebuild, use homebrew instead
        "duti"           # Set default file type associations on macOS
        "clamav"         # Antivirus — clamscan + freshclam for signature updates
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

        # AI / image generation
        "diffusionbee"     # Stable Diffusion GUI — Intel Mac compatible, manages models itself

        # Utilities
        "tailscale-app"    # VPN with tray icon (replaces nix-darwin service; renamed from tailscale)
        "caffeine"         # Prevent Mac from sleeping (menubar app)
        "xquartz"          # X11 server required by x2goclient on macOS
        "microsoft-remote-desktop"  # RDP client for OTworkstation xrdp sessions
        "sweet-home3d"     # Interior design and home planning

        # Security
        "osquery"          # Endpoint telemetry — installs LaunchDaemon for continuous monitoring

        # Video conferencing
        "zoom"
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
      age.sshKeyPaths = [];
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

    # nix-darwin only splices pre/extra/postActivation into the activate script;
    # custom-named system.activationScripts.<name> entries are silently dropped and
    # never run. All host activation logic must therefore live under postActivation.
    # Fragments are merged via mkMerge (text is types.lines, so they concatenate).
    system.activationScripts.postActivation.text = lib.mkMerge [
      # Fix ownership of sops-created directories (sops creates parent dirs as root)
      ''
        chown scott:staff /Users/scott/.local/share || true
        chown scott:staff /Users/scott/.local/share/bitwarden-secrets || true
      ''

      # Install BOSL2 library to OpenSCAD user libraries directory
      ''
        (
          OPENSCAD_LIB="/Users/scott/Library/Application Support/OpenSCAD/libraries"
          mkdir -p "$OPENSCAD_LIB"
          if [ ! -L "$OPENSCAD_LIB/BOSL2" ]; then
            rm -rf "$OPENSCAD_LIB/BOSL2"
            ln -sfn ${bosl2} "$OPENSCAD_LIB/BOSL2"
            chown -h scott:staff "$OPENSCAD_LIB/BOSL2" 2>/dev/null || true
          fi
        ) || true
      ''

      # NFS mounts for nas01 shares via Tailscale, mounted on-demand via autofs.
      # macOS has a sealed, read-only root volume, so /mnt cannot be created (that would
      # require an /etc/synthetic.conf firmlink + reboot, like /nix). Mount under the user's
      # home instead: ~/mnt/nas01/{SANS,photos}. Wrapped in a subshell + `|| true` so a
      # transient NFS/autofs hiccup can't abort the rest of activation.
      # NOTE: heredoc body/delimiter are intentionally at column 0 so Nix's `''` dedent
      # leaves them unindented (autofs needs the map lines and delimiter flush-left).
      ''
        (
          MNT="/Users/scott/mnt/nas01"
          mkdir -p "$MNT"
          chown scott:staff /Users/scott/mnt "$MNT" 2>/dev/null || true

          # autofs indirect map: $MNT/{SANS,photos} → nas01 exports
          cat > /etc/auto_nas01 << 'AUTOFSMAP'
SANS    -fstype=nfs,resvport,soft,timeo=30,intr,rw  nas01.warthog-royal.ts.net:/pool/shares/SANS
photos  -fstype=nfs,resvport,soft,timeo=30,intr,rw  nas01.warthog-royal.ts.net:/pool/shares/photos
AUTOFSMAP

          # Register the map in auto_master if not already present
          if ! grep -q '/Users/scott/mnt/nas01' /etc/auto_master; then
            echo '/Users/scott/mnt/nas01  auto_nas01  -nobrowse' >> /etc/auto_master
          fi

          # Reload autofs to pick up changes
          automount -vc 2>/dev/null || true
        ) || true
      ''

      # Wazuh security agent — install .pkg, enroll, and start LaunchDaemon.
      # Wrapped in a subshell so its `set -euo pipefail` + `trap EXIT` stay scoped,
      # and `|| true` so an offline/install failure can't abort activation (retries next rebuild).
      ''
        (
          set -euo pipefail

          WAZUH_MANAGER="wazuh.warthog-royal.ts.net"

          # --- Install ---
          if [ ! -f /Library/Ossec/etc/ossec.conf ]; then
            echo "Installing Wazuh agent ${wazuhVersion}..."
            TMPDIR=$(mktemp -d)
            trap 'rm -rf "$TMPDIR"' EXIT
            /usr/bin/curl -fsSL \
              "https://packages.wazuh.com/4.x/macos/wazuh-agent-${wazuhVersion}-1.intel64.pkg" \
              -o "$TMPDIR/wazuh-agent.pkg"
            # launchctl setenv required — installer spawns subprocesses that don't inherit shell env
            /bin/launchctl setenv WAZUH_MANAGER "$WAZUH_MANAGER"
            /usr/sbin/installer -pkg "$TMPDIR/wazuh-agent.pkg" -target /
            /bin/launchctl unsetenv WAZUH_MANAGER
            # Belt-and-suspenders: patch ossec.conf directly in case setenv wasn't picked up
            ${pkgs.gnused}/bin/sed -i \
              "s|<address>.*</address>|<address>$WAZUH_MANAGER</address>|" \
              /Library/Ossec/etc/ossec.conf
            echo "Wazuh agent installed."
          fi

          # --- Enroll ---
          # client.keys is created empty by the pkg; -s checks for non-zero size (i.e. enrolled)
          if [ -f /Library/Ossec/bin/agent-auth ] && [ ! -s /Library/Ossec/etc/client.keys ]; then
            echo "Enrolling Wazuh agent..."
            /Library/Ossec/bin/agent-auth \
              -m "$WAZUH_MANAGER" \
              -A "$(hostname -s)"
            echo "Wazuh agent enrolled."
          fi

          # --- Service ---
          # The .pkg installs /Library/LaunchDaemons/com.wazuh.agent.plist; load it if not running.
          if [ -f /Library/LaunchDaemons/com.wazuh.agent.plist ]; then
            /bin/launchctl list com.wazuh.agent >/dev/null 2>&1 || \
              /bin/launchctl load /Library/LaunchDaemons/com.wazuh.agent.plist 2>/dev/null || true
          fi
        ) || true
      ''

      # Ignore Tahoe upgrade so softwareupdate only offers Sequoia (15.x) updates
      ''
        /usr/sbin/softwareupdate --ignore "macOS Tahoe" 2>/dev/null || true
      ''

      # Enable SSH server (Remote Login)
      ''
        /usr/sbin/systemsetup -setremotelogin on > /dev/null 2>&1 || true
      ''
    ];

    # Borg backup to nas01 via launchd (macOS equivalent of systemd)
    launchd.daemons.borg-backup =
      let
        borgScript = pkgs.writeShellScript "borg-backup" ''
          set -euo pipefail

          BW_SECRETS="/Users/scott/.local/share/bitwarden-secrets"
          REPO="ssh://scott@nas01.warthog-royal.ts.net/pool/borg/airbook-darwin"
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
          export BORG_REMOTE_PATH="/run/current-system/sw/bin/borg"

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
