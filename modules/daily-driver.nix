{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  # wtfi2 — live, visual network path diagnostic that pinpoints which hop
  # (host/Wi-Fi/gateway/uplink/WAN/DNS/captive-portal) is breaking the
  # connection (https://github.com/kanywst/wtfi2). Not in nixpkgs; shipped
  # upstream only as a prebuilt glibc-dynamic binary, so fetch the release
  # tarball and autoPatchelf it.
  wtfi2Version = "0.10.0";
  wtfi2 = pkgs.stdenv.mkDerivation {
    pname = "wtfi2";
    version = wtfi2Version;
    src = pkgs.fetchurl {
      url = "https://github.com/kanywst/wtfi2/releases/download/v${wtfi2Version}/wtfi2-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-eDySR+Y+330AnxIaAYD9lUqTEpje2gxrMlb1YbNTozI=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    sourceRoot = "wtfi2-x86_64-unknown-linux-gnu";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      install -Dm755 wtfi $out/bin/wtfi
    '';
    meta = {
      description = "Live, visual network path diagnostic that pinpoints exactly where your connection dies";
      homepage = "https://github.com/kanywst/wtfi2";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "wtfi";
    };
  };
in
{
  imports = [
    inputs.self.nixosModules.games
    inputs.self.nixosModules."3d-printing"
    inputs.self.nixosModules.font
    inputs.self.nixosModules.printing
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.bitwarden-scott
    inputs.self.nixosModules.borg-backup
    inputs.self.nixosModules.home-design
    inputs.self.nixosModules.iphone
    inputs.self.nixosModules.syncthing-declarative
    inputs.self.nixosModules.vscode
    inputs.self.nixosModules.pdf
    inputs.self.nixosModules."kali-docker"
    inputs.tether.nixosModules.tether
    # Wazuh agent + the SMART / disk-usage feeds it ships (moved from latitude
    # 2026-11-26 so every daily driver is monitored).
    inputs.self.nixosModules.wazuh-agent
    inputs.self.nixosModules.smart-monitor
    inputs.self.nixosModules.disk-usage-monitor
    inputs.self.nixosModules.mcp-nixos
    inputs.home-manager.nixosModules.home-manager
    (inputs.self.homeConfigurations.scott).nixosModule
  ];

  config = {

    # Tether: wireless iPhone clipboard/file/SMS/notification bridge. Replaces
    # iphone.nix's USB-only libimobiledevice/ifuse setup (which never actually
    # worked), so that is switched off. Moved here from hosts/latitude on
    # 2026-11-26 so airbook gets it too; both laptops' adapter is hci0.
    services.iphone-usb.enable = false;
    programs.tether = {
      enable = true;
      wifi = {
        enable = true;
        openFirewall = true;
      };
      bluetooth = {
        enable = true;
        adapters = [ "hci0" ];
      };
      extensions = [ "firefox" "thunderbird" ];
    };

    # Fonts: managed by modules/font.nix
    my.fonts = {
      enable = true;
      documents = true;
      craft = true;
      printing3d = true;
      nerd = true;
      viewer = true;
    };


    # Fleet-management aliases: only meaningful on a machine used to administer
    # the other hosts, so kept out of shell-aliases.nix (imported by every host).
    environment.shellAliases = {
      nix-sync = "~/git/nixos/scripts/sync-nixos-hosts.sh";
      fw-check = "~/git/nixos/scripts/check-fw-updates.sh";
      host-status = "~/git/nixos/scripts/host-status.sh";

      # IDrive360 client shortcuts — same reasoning as the fleet aliases above:
      # useful from any daily driver, not tied to one host. Agent runs on
      # sands-bak01 (dedicated hardware, migrated off the nas01-backup VM,
      # which was decommissioned 2026-09-26 — see MIGRATION.md in the
      # idrive360 repo).
      #
      # Single-window remote view of just the IDrive360 GUI, no VNC — attaches
      # over SSH to the idrive360-xpra seamless session on sands-bak01.
      idrive-app = "xpra attach ssh://scott@sands-bak01.warthog-royal.ts.net/100";
      # Start/stop/restart the idrive360cron agent service on sands-bak01.
      idrive-start = "ssh scott@sands-bak01.warthog-royal.ts.net sudo systemctl start idrive360cron";
      idrive-stop = "ssh scott@sands-bak01.warthog-royal.ts.net sudo systemctl stop idrive360cron";
      idrive-restart = "ssh scott@sands-bak01.warthog-royal.ts.net sudo systemctl restart idrive360cron";

      # Herdr -h shortcuts — same targets as the "Tailscale SSH shortcuts" in
      # shell-aliases.nix, but through `herdr --remote` (pkgs.herdr below)
      # instead of a plain `tailscale ssh`. Herdr attaches to a persistent
      # remote session the way `tmux attach` attaches to a local one. Kept
      # here rather than shell-aliases.nix because the herdr binary is only
      # installed on daily-driver hosts.
      nas01-h = "herdr --remote nas01";
      backup-h = "herdr --remote sands-bak01";
      log01-h = "herdr --remote log01";
      pihole01-h = "herdr --remote pihole01";
      pihole02-h = "herdr --remote pihole02";
      latitude-h = "herdr --remote latitude";
      vm01-h = "herdr --remote vm01";
      otworkstation-h = "herdr --remote OTworkstation";
      work-debian-h = "herdr --remote sjensen@work-debian";
    };

    networking.networkmanager.enable = true;

    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    # Mac-parity shortcuts: when the Logitech keyboard is paired to the
    # MacBook, macOS auto-maps its Windows/Super key to Cmd with zero config
    # there. This mirrors that on latitude so Super+C/V/etc behaves like
    # Cmd+C/V does on the Mac, without touching the Mac side at all. Only
    # leftmeta is remapped, evdev-level via keyd so it works under both X11
    # and Wayland sessions; Ctrl itself is never touched, so a real Ctrl-C/
    # Ctrl-Z still SIGINTs/suspends in a terminal as normal. Copy/paste/cut
    # go to the X11-standard Ctrl-Insert/Shift-Insert/Shift-Delete bindings
    # (already honored by Konsole and xfce4-terminal with no extra config)
    # instead of literal Ctrl-C/V/X, so Super+C copies even with a terminal
    # focused instead of landing on SIGINT. Undo/select-all/find/save have no
    # such safe alternate binding, so those fall back to literal Ctrl-Z/A/F/S
    # — harmless almost everywhere, but Ctrl-Z suspends and Ctrl-S freezes
    # output (Ctrl-Q to resume) if one of those lands in a focused terminal.
    # Known trade-off: tapping Super alone to open the app launcher may stop
    # working, since keyd's layer() no longer passes through a bare tap.
    services.keyd = {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings = {
          main = {
            leftmeta = "layer(cmd)";
          };
          "cmd:M" = {
            c = "C-insert"; # copy
            v = "S-insert"; # paste
            x = "S-delete"; # cut
            z = "C-z";      # undo
            a = "C-a";      # select all
            f = "C-f";      # find
            s = "C-s";      # save
          };
        };
      };
    };

    # keyd grabs the built-in keyboard and re-emits it as "keyd virtual
    # keyboard", which libinput treats as external, so disable-while-typing
    # never pairs it with the touchpad (palms brush the trackpad mid-typing,
    # very noticeable on airbook's big Apple trackpad). Marking the virtual
    # keyboard internal restores DWT under both X11 and Wayland (KWin reads
    # libinput quirks directly; services.libinput.* above is X11-only).
    environment.etc."libinput/local-overrides.quirks".text = ''
      [keyd virtual keyboard]
      MatchUdevType=keyboard
      MatchName=keyd virtual keyboard
      AttrKeyboardIntegration=internal
    '';

    # Enable keyboard backlight control for laptops (Dell, Lenovo, etc.)
    services.udev.extraRules = ''
      # Allow members of video group to control keyboard backlight
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';

    programs.firefox.enable = true;
    # Thunderbird accounts/settings are not declared in Nix: the profile is set
    # up once and copied between daily drivers with `tb-push` (below), or
    # restored from borg on a rebuilt host.
    programs.thunderbird.enable = true;

    services.wazuh-agent = {
      enable = true;
      manager = "wazuh.warthog-royal.ts.net";
      enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
    };

    # mcp-nixos MCP server for Claude Code (NixOS/home-manager option lookups)
    programs.mcp-nixos.enable = true;

    # Default text editor for .txt and .conf files. mkDefault so a host can
    # pick its own (airbook-xfce uses Mousepad, hosts/airbook/desktop.nix).
    xdg.mime.defaultApplications = {
      "text/plain" = lib.mkDefault "geany.desktop";
      "text/x-config" = lib.mkDefault "geany.desktop";
    };

    # Syncthing Tray, preconfigured with this host's and nas01's Syncthing.
    sops.secrets."syncthing_nas01_apikey" = {
      owner = "scott";
    };

    systemd.user.services.syncthingtray = {
      description = "Syncthing Tray";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStartPre = pkgs.writeShellScript "syncthingtray-configure" ''
          LOCAL_KEY=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<apikey>)[^<]+' \
            "$HOME/.config/syncthing/config.xml")
          NAS01_KEY=$(cat /run/secrets/syncthing_nas01_apikey)

          ${pkgs.python3}/bin/python3 - "$LOCAL_KEY" "$NAS01_KEY" <<'PYEOF'
import configparser, sys, os
local_key, nas01_key = sys.argv[1], sys.argv[2]
path = os.path.join(os.environ['HOME'], '.config', 'syncthingtray.ini')
config = configparser.RawConfigParser()
config.optionxform = str
if os.path.exists(path):
    config.read(path)
if not config.has_section('tray'):
    config.add_section('tray')
for key, val in [
    (r'connections\1\apiKey',       f'@ByteArray({local_key})'),
    (r'connections\1\syncthingUrl', 'http://localhost:8384'),
    (r'connections\1\autoConnect',  'true'),
    (r'connections\1\label',        '${config.networking.hostName}'),
    (r'connections\2\apiKey',       f'@ByteArray({nas01_key})'),
    (r'connections\2\syncthingUrl', 'http://nas01.warthog-royal.ts.net:8384'),
    (r'connections\2\autoConnect',  'true'),
    (r'connections\2\label',        'nas01'),
    (r'connections\size',           '2'),
]:
    config.set('tray', key, val)
with open(path, 'w') as f:
    config.write(f, space_around_delimiters=False)
PYEOF
        '';
        ExecStart = "${pkgs.syncthingtray-minimal}/bin/syncthingtray --wait";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    environment.systemPackages = with pkgs; [
      anki
      geany
      gimp
      git-lfs  # GRFICSv3 OT lab (large Docker image assets)
      syncthingtray-minimal
      wtfi2    # network path diagnostic TUI (binary: wtfi)
      python3Minimal
      claude-code
      muse-code  # Meta's terminal coding agent (`muse`; unfree, allowed in common.nix)
      herdr  # terminal workspace manager for AI coding agents; see the -h aliases

      # tb-push: copy ~/.thunderbird from one daily driver to the others over
      # Tailscale SSH, refusing while Thunderbird runs on any of them
      # (source: scripts/tb-push.sh).
      (writeShellScriptBin "tb-push" (builtins.readFile ../scripts/tb-push.sh))
      # Claude desktop app is macOS/Windows only — no official Linux build or
      # nixpkgs package.

      # GPU-accelerated terminal emulator. Its terminfo entry already ships
      # system-wide via enableAllTerminfo in common.nix, so tmux and SSH'd-into
      # hosts handle TERM=xterm-ghostty without extra work.
      ghostty

      shotwell
      mpv

      # Pocket Casts: nixpkgs' Electron wrapper around play.pocketcasts.com
      # (no official Linux client).
      pocket-casts
      handbrake  # Video transcoding
      discord

      # Home Assistant: there is no official HA desktop/companion client for
      # Linux, so this is the community one (joshuar/go-hass-agent) — same role
      # as the official "home-assistant" companion app on macOS: it registers
      # the machine with HA as a device and reports sensors (battery, network,
      # power, app state) and receives notifications.
      #
      # Registration is automatic at login (the go-hass-agent unit below uses
      # the sops token home-assistant/agent_token). Manual equivalent, with a
      # long-lived access token from HA →
      # profile → security (HA listens on port 80, not 8123; this is HA's
      # advertised external URL, so it also works off-LAN over Tailscale):
      #   go-hass-agent register \
      #     --server https://homeassistant.warthog-royal.ts.net --token <token>
      # The go-hass-agent user service below then starts it at login.
      go-hass-agent

      # nixpkgs' go-hass-agent ships only the binary — upstream's own packages
      # include a .desktop file, so add the launcher entries by hand: one to
      # start the agent, one for HA's web dashboard. The agent entry starts
      # the systemd unit below rather than running the binary: a second copy
      # can't bind the agent's port (8223) and crashes the unit (airbook had
      # a menu-launched copy blocking it, 2026-11-26). Starting an
      # already-running unit does nothing.
      (makeDesktopItem {
        name = "go-hass-agent";
        desktopName = "Home Assistant Agent";
        comment = "Report this machine's sensors to Home Assistant";
        exec = "systemctl --user start go-hass-agent.service";
        categories = [ "Utility" ];
      })
      (makeDesktopItem {
        name = "home-assistant";
        desktopName = "Home Assistant";
        comment = "Jen Acres home automation dashboard";
        exec = "firefox --new-window https://homeassistant.warthog-royal.ts.net";
        categories = [ "Network" ];
      })

      libreoffice

      borgbackup
      unzip
      usbimager  # Write .img/.iso files to USB drives
      gparted    # Disk partitioning and formatting
      binutils   # strings, objdump, etc. — extract printable strings from binaries

      # 2D CAD
      librecad
      qcad

      # Backlight control (for screen and keyboard backlighting)
      brightnessctl

      xpra  # client for the idrive-app alias above

      # idrive-status — sands-bak01 is dedicated hardware, not a VM, so this
      # just SSHes straight in and runs idrive360-agent-status.sh (tracked in
      # ~/git/idrive360, deployed to /usr/local/bin there). A script rather
      # than a shell function so it works from any shell and can't be broken
      # by alias parse-order (see the unalias notes in hosts/nas01/default.nix).
      (writeShellScriptBin "idrive-status" ''
        ssh scott@sands-bak01.warthog-royal.ts.net /usr/local/bin/idrive360-agent-status.sh
      '')
    ];

    # HA long-lived access token for go-hass-agent registration (HA → profile
    # → security). One token shared by every daily driver; the agent also
    # keeps its own copy in preferences.toml once registered.
    sops.secrets."home-assistant/agent_token".owner = "scott";

    # Start go-hass-agent at login, registering it with HA first if needed.
    # "Registered" means `registered = true` in preferences.toml: an
    # unregistered first run also writes that file (just a [device] section),
    # so its mere existence proves nothing (latitude sat unregistered behind
    # that check 2026-11-19..26). If HA is unreachable, register fails and the
    # unit retries via Restart. Without the token (sops not set up yet) the
    # ExecCondition keeps the unit inactive instead of serving the web form.
    systemd.user.services.go-hass-agent = let
      prefs = "$HOME/.config/go-hass-agent/preferences.toml";
      token = config.sops.secrets."home-assistant/agent_token".path;
      isRegistered = ''${pkgs.gnugrep}/bin/grep -qx 'registered = true' "${prefs}" 2>/dev/null'';
    in {
      description = "Go Hass Agent — report sensors to Home Assistant";
      # pw-dump feeds the mic/webcam-in-use sensors.
      path = [ pkgs.pipewire ];
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecCondition = pkgs.writeShellScript "go-hass-agent-can-run" ''
          ${isRegistered} || [ -r ${token} ]
        '';
        ExecStartPre = pkgs.writeShellScript "go-hass-agent-register" ''
          ${isRegistered} && exit 0
          # --force: an unregistered first run leaves a partial config behind.
          exec ${pkgs.go-hass-agent}/bin/go-hass-agent register --force \
            --server https://homeassistant.warthog-royal.ts.net \
            --token "$(< ${token})"
        '';
        ExecStart = "${pkgs.go-hass-agent}/bin/go-hass-agent run";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib zstd bzip2 xz
        openssl libxcrypt libxcrypt-legacy
        curl libssh
        util-linux systemd attr acl libsodium
        libxml2 glib dbus
        libGL          # OpenCV / mediapipe / GPU ML backends
        libxcb         # OpenCV display support
      ];
    };
    my.printing = {
      enable = true;
      fonts.enable = true;
      repairTools = true;
      generateTestArtifacts = true;
    };
  };
}
