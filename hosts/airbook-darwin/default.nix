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

  # Wazuh borg-status telemetry: caches the borg passphrase from Bitwarden into a root-
  # only file so the status probe (below) can query the repo without an interactive bw
  # unlock every run. Mirrors the NixOS pattern where bitwarden-secrets-sync writes
  # /run/bitwarden-secrets/borg_passphrase at boot.
  wazuhBorgPasssync = pkgs.writeShellScript "wazuh-borg-passsync" ''
    set -euo pipefail
    BW_SECRETS="/Users/scott/.local/share/bitwarden-secrets"
    BW_BORG_ITEM_ID="91db7811-ddf1-49aa-8a42-b3d60188a6e6"

    # First-boot race: sops-nix may not have deployed the bitwarden secrets yet.
    for _ in $(seq 1 30); do
      [ -r "$BW_SECRETS/client_id" ] && break
      sleep 2
    done

    export BW_CLIENTID="$(cat "$BW_SECRETS/client_id")"
    export BW_CLIENTSECRET="$(cat "$BW_SECRETS/client_secret")"
    export BW_PASSWORD="$(cat "$BW_SECRETS/master_password")"
    # Isolate bw state to a tempdir so we don't leak session material into /var/root.
    HOME="$(mktemp -d)"; export HOME
    trap 'rm -rf "$HOME"' EXIT

    BW="/usr/local/bin/bw"
    "$BW" login --apikey --quiet 2>/dev/null || true
    BW_SESSION="$("$BW" unlock --passwordenv BW_PASSWORD --raw)"
    export BW_SESSION
    PASS="$("$BW" get item "$BW_BORG_ITEM_ID" | ${pkgs.jq}/bin/jq -r '.login.password')"
    "$BW" lock --quiet || true

    mkdir -p /etc/wazuh
    umask 077
    tmp="$(mktemp /etc/wazuh/borg.pass.XXXXXX)"
    printf '%s' "$PASS" > "$tmp"
    chmod 400 "$tmp"
    chown root:wheel "$tmp"
    mv -f "$tmp" /etc/wazuh/borg.pass
  '';

  # Wazuh logcollector runs this periodically; output is shipped to the manager as
  # `borg_backup: status=… repo=… archive=… start=… duration=…s age=…h`. Same format
  # as modules/borg-backup.nix so the manager's existing decoder/rule applies.
  wazuhBorgStatus = pkgs.writeShellScript "wazuh-borg-status" ''
    set -euo pipefail
    # borg lives in the current-system profile; PATH is minimal when logcollector invokes us.
    export PATH="/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    CONF=/etc/wazuh/borg.conf
    set -a; [ -f "$CONF" ] && . "$CONF"; set +a

    REPO="''${BORG_REPO:-}"
    STALE_HOURS="''${BORG_STALE_HOURS:-25}"

    if [ -z "$REPO" ]; then
      echo "borg_backup: status=ERROR repo=unset error=BORG_REPO_not_configured"
      exit 0
    fi
    if ! command -v borg >/dev/null 2>&1; then
      echo "borg_backup: status=ERROR repo=''${REPO} error=borg_not_found"
      exit 0
    fi

    LAST=$(borg list --last 1 --format '{archive}|{start:%Y-%m-%dT%H:%M:%S}' "$REPO" 2>&1) || {
      ERR=$(printf '%s' "$LAST" | head -1 | tr -cs '[:alnum:]_.-' '_' | cut -c1-60)
      echo "borg_backup: status=ERROR repo=''${REPO} error=''${ERR}"
      exit 0
    }
    if [ -z "$LAST" ]; then
      echo "borg_backup: status=EMPTY repo=''${REPO} error=no_archives"
      exit 0
    fi

    ARCHIVE=$(printf '%s' "$LAST" | cut -d'|' -f1)
    START=$(printf '%s' "$LAST" | cut -d'|' -f2)

    # macOS `date` uses -j -f; GNU `date -d` is unavailable.
    START_EPOCH=$(/bin/date -j -f '%Y-%m-%dT%H:%M:%S' "$START" +%s 2>/dev/null) || START_EPOCH=0
    AGE_H=$(( ($(/bin/date +%s) - START_EPOCH) / 3600 ))

    DURATION=$(borg info "''${REPO}::''${ARCHIVE}" --format '{duration:.0f}' 2>/dev/null || echo "0")

    if [[ "$ARCHIVE" == *.failed ]]; then
      echo "borg_backup: status=ERROR repo=''${REPO} archive=''${ARCHIVE} start=''${START} duration=''${DURATION}s age=''${AGE_H}h error=archive_marked_failed"
      exit 0
    fi

    STATUS=OK
    [ "$AGE_H" -gt "$STALE_HOURS" ] && STATUS=STALE
    echo "borg_backup: status=''${STATUS} repo=''${REPO} archive=''${ARCHIVE} start=''${START} duration=''${DURATION}s age=''${AGE_H}h"
  '';

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

      # MCP server for Claude Code (NixOS/nix-darwin package/option queries)
      uv

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
        # NOTE: no brew `tailscale`. The App Store macsys Tailscale.app (System Network
        # Extension) is the sole tailnet endpoint on this box — running two tailscaleds
        # side-by-side flapped DERP negotiation and killed long-running TCP sessions
        # (borg 30-min upload to nas01 was reset mid-transfer). Trade-off: no Tailscale
        # SSH server hosting from this Mac (the sandboxed extension can't); standard sshd
        # over the tailnet still works fine.
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
        "caffeine"         # Prevent Mac from sleeping (menubar app)
        "xquartz"          # X11 server required by x2goclient on macOS
        "microsoft-remote-desktop"  # RDP client for OTworkstation xrdp sessions
        "sweet-home3d"     # Interior design and home planning

        # Security
        "osquery"          # Endpoint telemetry — installs LaunchDaemon for continuous monitoring

        # macOS legacy hardware support — needed on MacBookAir7,2 for Sequoia (BDW iGPU + WiFi/BT).
        # Brew keeps /Applications/OpenCore-Patcher.app updated; the app installs the AutoPatcher
        # LaunchAgent (com.dortania.*.auto-patch) which prompts to re-apply root patches after
        # an OS update. It also drops the two LaunchDaemons bootstrapped in postActivation below.
        # After a brew upgrade of this cask, open the app once and re-run "Install AutoPatcher"
        # so the copy under /Library/Application Support/Dortania stays in sync.
        "opencore-patcher"

        # Flashcards / spaced repetition
        "anki"

        # Video conferencing
        "zoom"

        # Menubar plugin framework — hosts the syncthing status plugin declared via
        # home-manager (see hosts/airbook-darwin/home.nix). Keep-the-brew-daemon model,
        # unlike the `syncthing-app` cask which bundles its own daemon and would fight
        # the brew one over ~/Library/Application Support/Syncthing/.
        "swiftbar"
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

      # NFS mounts for nas01 shares via Tailscale, on-demand via autofs, at /mnt/nas01
      # (matches latitude).
      #
      # macOS specifics: the root volume is sealed and read-only. /etc/synthetic.conf gives
      # us an empty /mnt, but a single-token synthetic entry lives ON the read-only root —
      # it is a valid *mountpoint*, not a writable directory (this is why /nix works: Nix
      # mounts a separate APFS volume onto it). So automountd cannot mkdir /mnt/nas01 inside
      # it. Instead we mount autofs directly ONTO /mnt (mounting over a dir needs no write
      # access to it) and use an autofs multi-mount entry keyed `nas01`, which yields
      # /mnt/nas01/SANS and /mnt/nas01/photos. See auto_master(5) "multiple mounts".
      #
      # Wrapped in a subshell + `|| true` so a transient NFS/autofs hiccup can't abort the
      # rest of activation.
      # NOTE: heredoc body/delimiter are intentionally at column 0 so Nix's `''` dedent
      # leaves them unindented (autofs needs the map lines and delimiter flush-left).
      # The trailing backslashes are literal — Nix `''` strings do not process \ escapes.
      ''
        (
          # autofs mounts maps onto the writable data volume (/System/Volumes/Data/...).
          # /home gets away with a bare name because macOS firmlinks it; /mnt has no firmlink,
          # so a plain `mnt` synthetic entry would be an empty dir on the READ-ONLY root and
          # the mounts would be invisible there. Use synthetic.conf's symlink form instead:
          #   mnt<TAB>System/Volumes/Data/mnt
          # which points /mnt at exactly where autofs mounts. Takes effect after a REBOOT.
          # Rewrite idempotently, preserving the installer-managed nix/run entries.
          mkdir -p /System/Volumes/Data/mnt 2>/dev/null || true
          if ! grep -q '^mnt[[:space:]]*System/Volumes/Data/mnt$' /etc/synthetic.conf 2>/dev/null; then
            ${pkgs.gnused}/bin/sed -i -E '/^mnt([[:space:]]|$)/d' /etc/synthetic.conf
            printf 'mnt\tSystem/Volumes/Data/mnt\n' >> /etc/synthetic.conf
          fi

          # autofs multi-mount map: key `nas01` with /SANS and /photos sub-mounts
          cat > /etc/auto_nas01 << 'AUTOFSMAP'
nas01 \
	/SANS	-fstype=nfs,resvport,soft,timeo=30,rw	nas01.warthog-royal.ts.net:/pool/shares/SANS \
	/photos	-fstype=nfs,resvport,soft,timeo=30,rw	nas01.warthog-royal.ts.net:/pool/shares/photos
AUTOFSMAP

          # Manage the auto_master entry idempotently: drop any prior auto_nas01 line
          # (the old ~/mnt/nas01 and /mnt/nas01 paths) and mount the map on /mnt itself.
          ${pkgs.gnused}/bin/sed -i '/auto_nas01/d' /etc/auto_master 2>/dev/null || true
          echo '/mnt  auto_nas01  -nobrowse' >> /etc/auto_master

          # Reload autofs, then retire the previous ~/mnt/nas01 location (best-effort).
          automount -vc 2>/dev/null || true
          rmdir /Users/scott/mnt/nas01 /Users/scott/mnt 2>/dev/null || true
        ) || true
      ''

      # OpenCore Legacy Patcher — bootstrap the two WatchPath LaunchDaemons the OCLP.app
      # drops into /Library/LaunchDaemons. They are event-triggered, not RunAtLoad, so if
      # they aren't bootstrapped they silently do nothing when an OS update or RSR fires:
      #   macos-update  → runs OCLP --prepare_for_update when Update.plist appears
      #   rsr-monitor   → deletes AppleIntelBDWGraphics.kext before an RSR cryptex loads
      # (The user-session AutoPatcher LaunchAgent already RunAtLoads via loginwindow, so
      # no bootstrap needed for it.) `bootstrap` is idempotent with `|| true` — the second
      # run errors with "already loaded" which we ignore.
      ''
        for plist in \
          /Library/LaunchDaemons/com.dortania.opencore-legacy-patcher.macos-update.plist \
          /Library/LaunchDaemons/com.dortania.opencore-legacy-patcher.rsr-monitor.plist; do
          [ -f "$plist" ] || continue
          launchctl bootstrap system "$plist" 2>/dev/null || true
        done
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
            echo "Wazuh agent installed."
          fi

          # --- Patch ossec.conf (idempotent, always runs) ---
          # The pkg installs ossec.conf with a literal `MANAGER_IP` placeholder that the
          # WAZUH_MANAGER launchctl env var is supposed to substitute — but it doesn't
          # reliably. If a prior install stranded the config with the placeholder, the
          # daemon crashes with "Invalid server address 'MANAGER_IP'" every start. Running
          # this every activation heals that state; if the address is already correct it's
          # a no-op rewrite. `[^<]*` avoids greedy cross-tag matches.
          if [ -f /Library/Ossec/etc/ossec.conf ]; then
            ${pkgs.gnused}/bin/sed -i \
              "s|<address>[^<]*</address>|<address>$WAZUH_MANAGER</address>|" \
              /Library/Ossec/etc/ossec.conf
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
          # The .pkg installs /Library/LaunchDaemons/com.wazuh.agent.plist. `launchctl list`
          # only sees the current user's domain, so it always reports missing here and the
          # old `load` path silently no-op'd. Enable + bootstrap into the system domain
          # instead, and check via `launchctl print` (same pattern as sshd fix above).
          if [ -f /Library/LaunchDaemons/com.wazuh.agent.plist ]; then
            /bin/launchctl enable system/com.wazuh.agent 2>/dev/null || true
            /bin/launchctl print system/com.wazuh.agent >/dev/null 2>&1 || \
              /bin/launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist 2>/dev/null || true
          fi

          # --- Borg-status telemetry integration ---
          # Same pattern as modules/borg-backup.nix on NixOS: install a status probe at
          # /usr/local/bin/wazuh-borg-status, enable remote command execution so the
          # manager's shared agent.conf command entry takes effect, and add a local
          # `full_command` localfile stanza so this works even without a group push.
          NEED_KICKSTART=0

          # Install the status script (symlink to nix store)
          mkdir -p /usr/local/bin
          ln -sfn ${wazuhBorgStatus} /usr/local/bin/wazuh-borg-status

          # Enable remote_commands (default is 0 for security). Only write on change so
          # we don't kickstart wazuh needlessly.
          DESIRED_LIO='logcollector.remote_commands=1
wazuh_command.remote_commands=1'
          if [ -f /Library/Ossec/etc/ossec.conf ]; then
            CURRENT_LIO="$(cat /Library/Ossec/etc/local_internal_options.conf 2>/dev/null || true)"
            if [ "$DESIRED_LIO" != "$CURRENT_LIO" ]; then
              printf '%s\n' "$DESIRED_LIO" > /Library/Ossec/etc/local_internal_options.conf
              chmod 640 /Library/Ossec/etc/local_internal_options.conf
              NEED_KICKSTART=1
            fi

            # Add a local `full_command` localfile so the probe runs even if the manager
            # hasn't pushed a shared agent.conf entry for this host. Idempotent grep-guard.
            if ! ${pkgs.gnugrep}/bin/grep -q 'wazuh-borg-status' /Library/Ossec/etc/ossec.conf; then
              ${pkgs.gnused}/bin/sed -i \
                's|</ossec_config>|  <localfile>\n    <log_format>full_command</log_format>\n    <command>/usr/local/bin/wazuh-borg-status</command>\n    <alias>borg_backup</alias>\n    <frequency>3600</frequency>\n  </localfile>\n</ossec_config>|' \
                /Library/Ossec/etc/ossec.conf
              NEED_KICKSTART=1
            fi
          fi

          if [ "$NEED_KICKSTART" = "1" ]; then
            /bin/launchctl kickstart -k system/com.wazuh.agent 2>/dev/null || true
          fi
        ) || true
      ''

      # Ignore Tahoe upgrade so softwareupdate only offers Sequoia (15.x) updates
      ''
        /usr/sbin/softwareupdate --ignore "macOS Tahoe" 2>/dev/null || true
      ''

      # MagicDNS resolver: the App Store macsys Tailscale.app writes
      # /etc/resolver/warthog-royal.ts.net itself via its helper — no manual
      # activation needed. (Only the brew tailscaled required the workaround.)
    ];

    # Wazuh borg-status telemetry — repo/env for the status probe. Declarative so
    # `darwin-rebuild switch` reproduces the same config on any fresh install.
    environment.etc."wazuh/borg.conf" = {
      text = ''
        BORG_REPO="ssh://scott@nas01.warthog-royal.ts.net/pool/borg/airbook-darwin"
        BORG_PASSCOMMAND="cat /etc/wazuh/borg.pass"
        BORG_RSH="ssh -i /Users/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new"
        BORG_REMOTE_PATH=/run/current-system/sw/bin/borg
      '';
    };

    # Sync the borg passphrase from Bitwarden into /etc/wazuh/borg.pass so the
    # status probe can non-interactively query the repo. Runs at boot and every 6h.
    launchd.daemons.wazuh-borg-passsync = {
      serviceConfig = {
        Label = "com.local.wazuh-borg-passsync";
        ProgramArguments = [ "${wazuhBorgPasssync}" ];
        RunAtLoad = true;
        StartInterval = 21600;
        StandardOutPath = "/var/log/wazuh-borg-passsync.log";
        StandardErrorPath = "/var/log/wazuh-borg-passsync.error.log";
      };
    };

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

          # Auto-init if the repo is absent (e.g. after a deliberate `rm -rf` on nas01
          # when the passphrase diverges from the canonical Bitwarden one). Uses the
          # same repokey-blake2 mode as NixOS's services.borgbackup default. Errors
          # (including "repo already exists") are ignored — a real failure surfaces at
          # borg create below.
          ${pkgs.borgbackup}/bin/borg init --encryption=repokey-blake2 "$REPO" 2>/dev/null || true

          ${pkgs.borgbackup}/bin/borg create \
            --stats \
            --compression auto,zstd \
            --checkpoint-interval 1800 \
            --exclude-caches \
            --exclude "*/node_modules" \
            --exclude "*/.npm" \
            --exclude "*/.cargo" \
            --exclude "*/.rustup" \
            --exclude "*/.cache" \
            --exclude "*/Cache" \
            --exclude "*/Library/Caches" \
            --exclude "*/Library/Application Support/*/Cache" \
            --exclude "*/Library/Mobile Documents" \
            --exclude "*/Library/CloudStorage" \
            --exclude "*/Library/Containers/com.apple.CloudDocs*" \
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
