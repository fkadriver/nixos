{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.self.nixosModules.tailscale
  ];

  config = {
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

    # Pi-hole owns port 53 — disable resolved's stub listener so it doesn't conflict.
    # resolved is enabled by tailscale.nix, so we force it off here.
    services.resolved = lib.mkForce { enable = false; };

    # Use Pi-hole for local DNS with Quad9 as an out-of-band fallback during boot
    networking.nameservers = lib.mkDefault [ "127.0.0.1" "9.9.9.9" ];

    # Local DNS entries — shared across all Pi-hole instances
    networking.extraHosts = ''
      192.168.10.21 unifi
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
          specialDomains = {
            # Block iCloud Private Relay to prevent Apple devices bypassing Pi-hole
            iCloudPrivateRelay = false;
          };
        };
        webserver.interface.theme = "default-dark";
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

    # Password hash injected via environment variable so it survives nixos-rebuild.
    # FTLCONF_ env vars override the corresponding pihole.toml settings at runtime.
    # Store the BALLOON-SHA256 hash in secrets.yaml as pihole/pwhash.
    # Get it from an existing Pi-hole: sudo grep app_pwhash /etc/pihole/pihole.toml
    # Copy the full value after the = sign (the $BALLOON-SHA256$... string)
    sops = {
      defaultSopsFile = lib.mkDefault ../secrets/secrets.yaml;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets."pihole/pwhash" = {};

      templates."pihole-ftl-env" = {
        content = "FTLCONF_webserver_api_app_pwhash=${config.sops.placeholder."pihole/pwhash"}\n";
        owner = config.services.pihole-ftl.user;
        mode = "0400";
      };
    };

    # Feed the password hash to pihole-ftl without baking it into the nix store
    systemd.services.pihole-ftl.serviceConfig.EnvironmentFile =
      [ config.sops.templates."pihole-ftl-env".path ];

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
