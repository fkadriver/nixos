{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  imports = [
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.tailscale
  ];

  config = {
    # bitwarden-cli 2025.12.1 fails to build on aarch64 because msgpackr-extract's
    # native module (node-gyp) hits a Python/str-vs-int type error. Override it to
    # skip native module compilation; bitwarden-cli falls back to pure-JS msgpackr.
    nixpkgs.overlays = [
      (final: prev: {
        bitwarden-cli = prev.bitwarden-cli.overrideAttrs (old: {
          # npmConfigHook is a postPatch hook that runs:
          #   npm ci --ignore-scripts   (creates node_modules)
          #   npm rebuild               (FAILS: msgpackr-extract binding.gyp has
          #                             a Python-3.12-incompatible >= comparison)
          #
          # Define a bash 'npm' function in postPatch (which runs before
          # postPatchHooks). Bash functions shadow external commands in the same
          # shell, so when npmConfigHook calls 'npm rebuild', our function fires
          # first — it replaces msgpackr-extract's binding.gyp with an empty
          # no-op target so node-gyp succeeds without building native code.
          # msgpackr transparently falls back to pure JS.
          postPatch = (old.postPatch or "") + ''
            npm() {
              if [[ "''${1-}" == rebuild ]]; then
                local f="$PWD/node_modules/msgpackr-extract/binding.gyp"
                [[ -f "$f" ]] && printf '{"variables":{},"targets":[]}' > "$f"
              fi
              command npm "$@"
            }
          '';
        });
      })
    ];
    # Slim package set — only what's needed for Pi-hole operation and git
    environment.systemPackages = with pkgs; [
      age     # encryption tool for SOPS
      sops    # secret operations
      vim
      git
      curl
      wget
      htop
    ];

    nixpkgs.config.allowUnfree = true;

    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocaleSettings = {
        LC_ADDRESS        = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT    = "en_US.UTF-8";
        LC_MONETARY       = "en_US.UTF-8";
        LC_NUMERIC        = "en_US.UTF-8";
        LC_PAPER          = "en_US.UTF-8";
        LC_TELEPHONE      = "en_US.UTF-8";
        LC_TIME           = "en_US.UTF-8";
      };
    };

    nix = {
      settings.experimental-features = [ "nix-command" "flakes" ];
      gc = {
        automatic = true;
        dates     = "weekly";
        options   = "--delete-older-than 30d";
      };
    };

    environment.shellAliases = {
      # Pi-hole service management
      ph-status  = "systemctl status pihole-ftl";
      ph-restart = "sudo systemctl restart pihole-ftl";
      ph-logs    = "journalctl -u pihole-ftl -f";
      ph-gravity = "sudo pihole updateGravity";

      # Tailscale SSH shortcuts (connect to other piholes)
      ts-ssh-pihole01 = "tailscale ssh scott@pihole01";
      ts-ssh-pihole02 = "tailscale ssh scott@pihole02";

      # Basic utils
      ll = "ls -lah";
      ".." = "cd ..";
    };

    programs = {
      git = {
        enable = true;
        config = {
          user.name  = "Scott Jensen";
          user.email = "fkadriver@gmail.com";
        };
      };
      tmux = {
        enable    = true;
        clock24   = true;
        keyMode   = "vi";
        terminal  = "screen-256color";
        historyLimit = 10000;
        extraConfig = ''
          set -g mouse on
          set -g base-index 1
          setw -g pane-base-index 1
          set -g renumber-windows on
          set -g status-style 'bg=#333333 fg=#ffffff'
          set -g status-right '%H:%M %d-%b-%y'
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind h select-pane -L
          bind j select-pane -D
          bind k select-pane -U
          bind l select-pane -R
        '';
      };
      bash = {};
      starship.enable = true;
    };

    time.timeZone = "America/Chicago";

    # Accept unsigned nix store paths from the build machine (latitude builds locally
    # and copies over SSH; paths aren't signed with a trusted key)
    nix.settings.require-sigs = false;

    # ── Minimal kernel footprint ──────────────────────────────────────────────
    # Restrict supported filesystems to what the Pi actually uses.
    # This is the biggest win: prevents ZFS kernel module from being built/included
    # (ZFS compilation on aarch64 via QEMU was the longest part of the initial build).
    boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" ];

    # Headless server — no audio hardware or use case
    hardware.bluetooth.enable = false;

    # Blacklist kernel modules not needed on a headless wired-only Pi-hole server
    boot.blacklistedKernelModules = [
      # Sound subsystem
      "snd" "snd_pcm" "snd_timer" "snd_seq" "snd_seq_device"
      # Wi-Fi (using wired ethernet only; Pi 3B: brcmfmac, Pi 4B: brcmfmac)
      "brcmfmac" "brcmutil" "cfg80211"
      # Bluetooth (Pi onboard BT — unused)
      "bluetooth" "btbcm" "hci_uart"
    ];

    # Tailscale accepts OPNsense's subnet routes, which override direct VLAN routing
    # and break LAN connectivity. These rules ensure local traffic uses the direct
    # interface so DNS responses go back via eth0, not through Tailscale.
    # (pihole.nix doesn't import common.nix, so the fix must be repeated here)
    networking.localCommands = ''
      ${pkgs.iproute2}/bin/ip rule add to 192.168.0.0/20 priority 100 table main 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule add to 192.168.16.0/20 priority 101 table main 2>/dev/null || true
    '';

    # Pi-hole owns port 53 — disable resolved's stub listener so it doesn't conflict.
    # resolved is enabled by tailscale.nix, so we force it off here.
    services.resolved = lib.mkForce { enable = false; };

    # Use Pi-hole for local DNS with Quad9 as an out-of-band fallback during boot
    networking.nameservers = lib.mkDefault [ "127.0.0.1" "9.9.9.9" ];

    # Local DNS entries — shared across all Pi-hole instances
    networking.extraHosts = ''
      192.168.10.21 unifi
      192.168.1.2   sw01  # HP1920
      192.168.1.3   sw02  # TL-SG108E
    '';

    # Pi-hole FTL daemon
    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;

      # Block and allow lists — managed here; user-added lists via Pi-Remote persist in gravity.db
      lists = [
        {
          url = "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/adblock/multi.txt";
          type = "block";
          enabled = true;
          description = "Hagezi Multi blocklist";
        }
        {
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/adblock/whitelist-referral-native.txt";
          type = "allow";
          enabled = true;
          description = "Hagezi Referral Native allowlist";
        }
      ];

      settings = {
        dns = {
          upstreams = [ "9.9.9.9" "149.112.112.112" ];
          dnssec = true;
          # Serve all interfaces so LAN clients can use Pi-hole for DNS
          listeningMode = "ALL";
          # Reply with Pi-hole's IP address for blocked queries (vs null/NXDOMAIN)
          blocking.mode = "IP";
          # Conditional forwarding — forward reverse lookups for each VLAN
          # to the corresponding gateway so Pi-hole resolves local hostnames.
          revServers = [
            "true,192.168.1.0/24,192.168.1.1"
            "true,192.168.10.0/24,192.168.10.1"
            "true,192.168.11.0/24,192.168.11.1"
            "true,192.168.20.0/24,192.168.20.1"
            "true,192.168.21.0/24,192.168.21.1"
          ];
          specialDomains = {
            # Block iCloud Private Relay to prevent Apple devices bypassing Pi-hole
            iCloudPrivateRelay = false;
          };
        };
        webserver = {
          interface.theme = "default-dark";
          api = {
            # Exclude local infrastructure from Top Domain/Client lists and query log
            excludeDomains = [ "^unifi$" "^unifi\\.lan$" ];
            excludeClients = [ "^unifi$" "^unifi\\.lan$" ];
          };
        };
        # pihole.toml is regenerated on each rebuild — block API config changes from the web UI
        misc.readOnly = true;
      };
    };

    # Pi-hole web admin interface (ports: plain number = HTTP, "Ns" suffix = HTTPS)
    services.pihole-web = {
      enable = true;
      ports = [ "80" ];
    };

    # Open HTTP/HTTPS for the web UI (pihole-web handles ports, but firewall must allow them)
    networking.firewall.allowedTCPPorts = [ 22 80 443 ];

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    # Fetch the Pi-hole web UI password hash from Bitwarden at boot.
    # The "Pi-Hole" item's password field holds the BALLOON-SHA256 hash.
    # FTLCONF_ env vars override the corresponding pihole.toml settings at runtime.
    services.bitwarden = {
      enable = true;
      secrets.pihole_pwhash = {
        name = "pihole_pwhash";
        itemId = "Pi-Hole";
        field = "password";
        owner = config.services.pihole-ftl.user;
        mode = "0400";
      };
    };

    # Convert the raw hash from /run/bitwarden-secrets/ into an env-file for pihole-ftl.
    systemd.services.pihole-pwhash-env = {
      description = "Write Pi-hole password env file from Bitwarden secret";
      after    = [ "bitwarden-secrets-sync.service" ];
      requires = [ "bitwarden-secrets-sync.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "pihole-pwhash-env" ''
          printf 'FTLCONF_webserver_api_app_pwhash=%s\n' \
            "$(< /run/bitwarden-secrets/pihole_pwhash)" \
            > /run/pihole-ftl-env
          chmod 0400 /run/pihole-ftl-env
          chown ${config.services.pihole-ftl.user} /run/pihole-ftl-env
        '';
      };
    };

    # Feed the password hash to pihole-ftl without baking it into the nix store
    systemd.services.pihole-ftl = {
      after    = [ "pihole-pwhash-env.service" ];
      requires = [ "pihole-pwhash-env.service" ];
      serviceConfig.EnvironmentFile = [ "/run/pihole-ftl-env" ];
    };

    # Expose Pi-hole web UI over Tailscale with HTTPS (tailnet-only, not public)
    # Accessible at https://pihole0x.<tailnet>.ts.net after Tailscale authenticates.
    systemd.services.tailscale-serve-pihole = {
      description = "Configure Tailscale Serve for Pi-hole web UI";
      after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Wait for Tailscale to authenticate before configuring serve
        ExecStartPre = pkgs.writeShellScript "wait-for-tailscale" ''
          until tailscale status >/dev/null 2>&1; do
            sleep 2
          done
        '';
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg http://localhost:80";
      };
    };
  };
}
