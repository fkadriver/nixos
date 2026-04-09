{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  imports = [
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.tailscale
  ];

  options.pihole.lockedKernelVersion = lib.mkOption {
    type = lib.types.str;
    description = ''
      Expected kernel version for this Pi. Set per-host in hosts/pihole*/default.nix.
      The build fails if the actual kernel drifts from this value (e.g. after
      nix flake update), forcing a deliberate acknowledgement before a 2-hour
      recompile is triggered. Update alongside LOCKED_KERNEL_VERSIONS in
      scripts/deploy-piholes.sh.
    '';
  };

  config = {

    assertions = [{
      assertion = config.boot.kernelPackages.kernel.version == config.pihole.lockedKernelVersion;
      message = "Pi kernel changed to ${config.boot.kernelPackages.kernel.version} "
              + "(locked: ${config.pihole.lockedKernelVersion}). Update "
              + "pihole.lockedKernelVersion in the host config and "
              + "LOCKED_KERNEL_VERSIONS in scripts/deploy-piholes.sh if intentional.";
    }];
    # bitwarden-cli 2025.12.1 fails to build on aarch64 because msgpackr-extract's
    # native module (node-gyp) hits a Python/str-vs-int type error. Override it to
    # skip native module compilation; bitwarden-cli falls back to pure-JS msgpackr.
    nixpkgs.overlays = [
      (final: prev: {
        # rsyslog's configure checks for libgcrypt via pkg-config, which is unavailable
        # in the x86_64→aarch64 cross environment. The piholes only do plain TCP
        # forwarding to log01 and don't need TLS/gcrypt features.
        rsyslog = prev.rsyslog.overrideAttrs (old: {
          configureFlags = (old.configureFlags or []) ++ [ "--disable-libgcrypt" ];
        });

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
                local dir="$PWD/node_modules/msgpackr-extract"
                if [[ -d "$dir" ]]; then
                  # Remove binding.gyp and strip gypfile from package.json so
                  # npm rebuild doesn't invoke node-gyp for this module at all.
                  # Use node (guaranteed present) to edit the JSON safely.
                  rm -f "$dir/binding.gyp"
                  node -e "
                    var fs = require('fs'), f = '$dir/package.json';
                    var p = JSON.parse(fs.readFileSync(f, 'utf8'));
                    delete p.gypfile;
                    if (p.scripts) delete p.scripts.install;
                    fs.writeFileSync(f, JSON.stringify(p));
                  " 2>/dev/null || true
                fi
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

    # Forward syslog and pihole DNS query logs to log01.
    # pihole-FTL logs DNS queries to /var/log/pihole/pihole.log (not syslog), so
    # imfile tails that file and injects entries into rsyslog's pipeline for forwarding.
    services.rsyslogd = {
      enable = true;
      extraConfig = ''
        # Tail pihole DNS query log and inject into rsyslog pipeline.
        # freshStartTail: on first run (no state file) start from the END of
        # the file so we don't replay potentially gigabytes of history.
        # After that, the state file tracks our position across rsyslog restarts.
        module(load="imfile" Mode="inotify")
        input(type="imfile"
          File="/var/log/pihole/pihole.log"
          Tag="pihole-dns"
          Facility="local3"
          Severity="info"
          freshStartTail="on")

        # Forward all messages (syslog + pihole DNS queries) to log01
        action(type="omfwd"
          target="log01.warthog-royal.ts.net"
          port="514"
          protocol="tcp"
          queue.type="LinkedList"
          queue.filename="log01fwd"
          queue.maxdiskspace="200m"
          queue.saveonshutdown="on"
          action.resumeRetryCount="-1"
          action.resumeInterval="30")
      '';
    };

    # Use Pi-hole for local DNS with Cloudflare malware-blocking as out-of-band fallback during boot
    networking.nameservers = lib.mkDefault [ "127.0.0.1" "1.1.1.2" ];

    # Local DNS entries — shared across all Pi-hole instances
    networking.extraHosts = ''
      192.168.10.21 unifi
      192.168.10.22 syslog-server
      192.168.1.2   aruba2530  # HPE Aruba 2530-24G PoE+ (SW01)
      192.168.1.3   sw02  # TL-SG108E
      192.168.11.50 LBP162  # Canon LBP
      192.168.11.51 Ender3V3KE   # Creality Ender-3 KEv3
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
        # misc.syslog sends FTL's own process logs to syslog (startup, errors, etc.)
        # DNS query logs go to files.log.dnsmasq (/var/log/pihole/pihole.log) — not syslog.
        # rsyslogd tails that file via imfile and forwards queries to log01.
        misc.syslog = true;
        # Allow pihole-set-password to write pwhash via pihole-FTL --config.
        # The NixOS pihole-ftl module defaults misc.readOnly = true (preventing all
        # config writes), which silently blocks pwhash from being set.
        misc.readOnly = false;

        dns = {
          # Primary: Cloudflare malware-blocking DoH (1.1.1.2/1.0.0.2)
          # The pipe-delimited IPs are bootstrap hints so FTL can reach the DoH
          # endpoint without a prior DNS lookup.
          # Tertiary: Google plain DNS as fallback.
          upstreams = [
            "https://security.cloudflare-dns.com/dns-query|1.1.1.2,1.0.0.2"
            "8.8.8.8"
          ];
          # DoH providers validate DNSSEC on their end; FTL-level DNSSEC validation
          # is left enabled — Cloudflare malware DoH supports DNSSEC passthrough.
          dnssec = true;
          # Serve all interfaces so LAN clients can use Pi-hole for DNS
          listeningMode = "ALL";
          # Reply with Pi-hole's IP address for blocked queries (vs null/NXDOMAIN)
          blocking.mode = "IP";
          # Conditional forwarding — forward reverse lookups for each VLAN
          # to the corresponding gateway so Pi-hole resolves local hostnames.
          # Dnsmasq listens on port 5353 (port 53 is taken by Unbound on OPNsense).
          # Append #5353 so Pi-hole sends PTR queries to the right port.
          revServers = [
            "true,192.168.1.0/24,192.168.1.1#5353"
            "true,192.168.10.0/24,192.168.10.1#5353"
            "true,192.168.11.0/24,192.168.11.1#5353"
            "true,192.168.20.0/24,192.168.20.1#5353"
            "true,192.168.21.0/24,192.168.21.1#5353"
            "true,192.168.30.0/24,192.168.30.1#5353"
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

    # Fetch the Pi-hole web password (plaintext) from Bitwarden at boot.
    # The "Pi-Hole" item's password field holds the plaintext web UI password.
    services.bitwarden = {
      enable = true;
      secrets.pihole_pwhash = {
        name = "pihole_pwhash";
        itemId = "Pi-Hole";
        field = "password";
        owner = "root";
        mode = "0400";
      };
    };

    # Set the Pi-hole web password before pihole-ftl starts.
    # pihole-FTL --config hashes the plaintext using BALLOON-SHA256 before writing to pihole.toml.
    # RemainAfterExit must be absent (false) so this service re-runs on every pihole-ftl
    # restart. With RemainAfterExit = true, systemd sees the service as "active" and skips
    # re-running it even after pihole-ftl is restarted (e.g. after nixos-rebuild switch),
    # causing the pwhash to be lost because pihole.toml is regenerated from Nix on rebuild.
    systemd.services.pihole-set-password = {
      description = "Set Pi-hole web password from Bitwarden secret";
      after    = [ "bitwarden-secrets-sync.service" ];
      requires = [ "bitwarden-secrets-sync.service" ];
      before   = [ "pihole-ftl.service" ];
      wantedBy = [ "pihole-ftl.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "pihole-set-password" ''
          ${pkgs.pihole-ftl}/bin/pihole-FTL \
            --config webserver.api.password \
            "$(< /run/bitwarden-secrets/pihole_pwhash)"
        '';
      };
    };

    systemd.services.pihole-ftl = {
      after    = [ "pihole-set-password.service" ];
      requires = [ "pihole-set-password.service" ];
    };

    # Rotate pihole's DNS query log daily — it grows quickly (1 DNS entry per line)
    # and is not rotated by the upstream pihole-ftl NixOS module.
    # After rotation, send SIGHUP to rsyslog so imfile re-opens the new file.
    services.logrotate.settings.pihole-dns = {
      files = "/var/log/pihole/pihole.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      dateext = true;
      missingok = true;
      notifempty = true;
      postrotate = "systemctl kill -s HUP syslog.service 2>/dev/null || true";
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
