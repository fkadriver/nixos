{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, tsDockerSidecarStart, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.tsauth
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.vscode-server
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.smart-monitor
      inputs.self.nixosModules.disk-usage-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.fwupd
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
    ];

    config = {
      # No override needed anymore — the fleet-wide target is the
      # Tailscale-fronted collector (currently nas01), not log01 itself,
      # so log01 forwarding its own local syslog there is no longer a
      # self-loop. Uses logging.forwardSyslog's default (true) like every
      # other host.

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
      };

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      networking = {
        hostName = "log01";
        networkmanager.enable = true;
        firewall = {  
          allowedTCPPorts = [ 514 ];
          allowedUDPPorts = [ 514 ];
        };
      };

      # SSH access (headless server)
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };

      # rsyslog: receive syslog from network devices on UDP/TCP 514
      # Logs stored locally at /var/log/remote/<hostname>/<program>.log
      # (unchanged path/behavior) AND relayed on to nas01's quota'd
      # pool/rsyslog dataset (see hosts/nas01/default.nix), which runs its
      # own receiver and is the long-term copy. Local storage here is now
      # just a short-retention resilience buffer (see logrotate below) in
      # case nas01 is briefly unreachable — nas01's root disk filling to
      # 100% on 2026-10-25 is exactly why this isn't the only copy anymore,
      # and why local retention is kept short with a maxsize backstop.
      # NOTE: do not add a forward action that all messages pass through unless it
      # has its own bounded queue with discard — a dead target (like the retired
      # Splunk host) backpressures the main queue, stalls imtcp reads, and wedges
      # every sender's forward queue fleet-wide (Jun-Jul 2026 outage). The
      # relay-to-nas01 action below reuses common.nix's already-proven
      # disk-assisted queue pattern for exactly this reason.
      services.rsyslogd = {
        enable = true;
        extraConfig = ''
          # Load input modules for remote syslog reception
          module(load="imudp")
          module(load="imtcp")

          input(type="imudp" port="514")
          input(type="imtcp" port="514")

          # Per-host log file path template
          template(name="RemoteHost" type="string"
            string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")

          # Per-host log message format: RFC 3164 (traditional syslog) timestamp so
          # Wazuh's syslog pre-decoder extracts hostname and program_name correctly.
          # RFC 3339 (ISO) timestamps cause Wazuh to skip hostname extraction, breaking
          # predecoder.hostname and making it impossible to filter by source host in OSD.
          # Pi-hole sends Tag="pihole-dns:" (colon included) so %syslogtag% already
          # satisfies Wazuh's requirement for a colon after the program name.
          $template WazuhSyslog,"%TIMESTAMP:::date-rfc3164% %HOSTNAME% %syslogtag%%msg%\n"

          $FileOwner root
          $FileGroup adm
          $FileCreateMode 0640
          $DirOwner root
          $DirGroup adm
          $DirCreateMode 0750
          :fromhost-ip, !isequal, "127.0.0.1"   ?RemoteHost;WazuhSyslog

          # Relay the same messages on to the universal collector
          # (syslog-tailscale repo, currently running on nas01 — see its
          # README) — except nas01's own traffic. Every NixOS host
          # (including nas01) now forwards its own syslog directly there
          # via common.nix's logging.forwardSyslog; relaying nas01's own
          # traffic back to it here would round-trip and double-ingest in
          # Wazuh. log01 itself stays as a transitional bridge for devices
          # that can't be repointed yet (OPNsense, pihole). Same
          # disk-assisted queue pattern as that existing forward action —
          # bounded, retries instead of blocking, so a slow/unreachable
          # collector can't backpressure imtcp/imudp reads and wedge every
          # sender fleet-wide (the Jun-Jul 2026 failure mode noted above).
          if $fromhost-ip != "127.0.0.1" and $fromhost-ip != "100.73.114.76" then {
            action(type="omfwd"
              target="syslog.warthog-royal.ts.net"
              port="5515"
              protocol="tcp"
              queue.type="LinkedList"
              queue.filename="collectorfwd"
              queue.maxdiskspace="500m"
              queue.saveonshutdown="on"
              action.resumeRetryCount="-1"
              action.resumeInterval="30")
          }

          :fromhost-ip, !isequal, "127.0.0.1"   ~
        '';
      };

      # Wazuh Docker Compose stack — all secrets fetched from Bitwarden at boot
      services.bitwarden.secrets.wazuh_username = {
        name = "wazuh_username";
        itemId = "c6077703-deef-4684-bb9d-b48601451e64";
        field = "username";
        mode = "0400";
      };
      services.bitwarden.secrets.wazuh_password = {
        name = "wazuh_password";
        itemId = "c6077703-deef-4684-bb9d-b48601451e64";
        field = "password";
        mode = "0400";
      };
      # Fine-grained PAT, Actions:read only, scoped to exactly the repos
      # wazuh-github-ci-status polls (tailnet, Fortydeux-NixOS-System-Flake,
      # photoAlbumOrganizer, SANS) — see wazuh-tailscale README.
      services.bitwarden.secrets.github_actions_token = {
        name = "github_actions_token";
        itemId = "fb798cd1-0355-438a-bb07-b496015dddae";
        field = "password";
        mode = "0400";
      };

      systemd.services.wazuh-docker = {
        description = "Wazuh Docker Compose Stack";
        wantedBy = [ "multi-user.target" ];
        after = [ "bitwarden-secrets-sync.service" "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "bitwarden-secrets-sync.service" "docker.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/scott/git/wazuh-tailscale";
          ExecStartPre =
            let python = pkgs.python3.withPackages (ps: [ ps.bcrypt ]);
            in pkgs.writeShellScript "wazuh-write-secrets" ''
              set -euo pipefail
              REPO=/home/scott/git/wazuh-tailscale

              # authd.pass — agent enrollment password
              rm -rf "$REPO/config/wazuh_cluster/authd.pass"
              cp /run/bitwarden-secrets/wazuh_agent_enrollment_password \
                "$REPO/config/wazuh_cluster/authd.pass"
              chmod 600 "$REPO/config/wazuh_cluster/authd.pass"

              # internal_users.yml — base users + Bitwarden admin user
              WAZUH_USERNAME=$(cat /run/bitwarden-secrets/wazuh_username)
              WAZUH_HASH=$(cat /run/bitwarden-secrets/wazuh_password \
                | ${python}/bin/python3 -c "
              import bcrypt, sys
              pw = sys.stdin.buffer.read().rstrip(b'\n')
              print(bcrypt.hashpw(pw, bcrypt.gensalt(12)).decode())
              ")
              cp "$REPO/config/wazuh_indexer/internal_users.yml.base" \
                 "$REPO/config/wazuh_indexer/internal_users.yml"
              printf '\n%s:\n  hash: "%s"\n  reserved: false\n  backend_roles:\n  - "admin"\n  description: "Bitwarden managed admin"\n' \
                "$WAZUH_USERNAME" "$WAZUH_HASH" \
                >> "$REPO/config/wazuh_indexer/internal_users.yml"
              chmod 600 "$REPO/config/wazuh_indexer/internal_users.yml"
            '';
          ExecStart = tsDockerSidecarStart;
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Stamps data.client_hostname onto recent Pi-hole DNS query events from
      # OPNsense DHCP lease data already indexed in wazuh-alerts-* — there's
      # no ingest-pipeline enrich processor on this wazuh-indexer build, so
      # this does the join after the fact via _update_by_query instead of at
      # index time. See wazuh-tailscale README's "DNS hostname enrichment"
      # section. Unlike wazuh-github-ci-status/wazuh-tailscale-health above,
      # this doesn't need a Nix-store copy for purity — it only needs docker
      # on PATH and the wazuh-tailscale repo checked out, so it runs straight
      # from that checkout instead of going through readFile + writeShellScript.
      systemd.timers.wazuh-dns-enrich = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "5m";
        };
      };
      systemd.services.wazuh-dns-enrich = {
        description = "Enrich Pi-hole DNS events with DHCP client hostnames";
        after = [ "wazuh-docker.service" ];
        path = [ pkgs.docker pkgs.jq pkgs.bash ];
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/home/scott/git/wazuh-tailscale";
          ExecStart = "${pkgs.bash}/bin/bash /home/scott/git/wazuh-tailscale/config/wazuh_dashboard/enrich-dns-hostnames.sh";
        };
      };

      # goflow2 Netflow collector — standalone from the Wazuh stack, writes
      # NDJSON flow records into the same directory rsyslog uses for OPNsense's
      # other forwarded logs (see goflow2-netflow repo + wazuh-tailscale's
      # shared/default/agent.conf for how Wazuh picks it up).
      systemd.services.goflow2-docker = {
        description = "goflow2 Netflow Collector";
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "docker.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/scott/git/goflow2-netflow";
          ExecStart = "${pkgs.docker}/bin/docker compose up -d";
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Ensure remote log directory and root SSH dir exist with correct permissions.
      # OPNsense.internal is called out explicitly (not just the parent dir) so
      # goflow2-docker has somewhere to bind-mount even before rsyslog has ever
      # received anything from OPNsense.
      #
      # wazuh-github-ci-status: deployed via "L+" symlink (same mechanism
      # borg-backup.nix uses for wazuh-borg-status). Flakes evaluate purely,
      # so this reads ./wazuh-github-ci-status.sh (in this repo, alongside
      # this file) rather than the wazuh-tailscale repo directly — that repo
      # keeps the documented canonical copy; this is a synced duplicate, same
      # relationship borg-backup.nix already has with wazuh-borg-status.sh.
      systemd.tmpfiles.rules = [
        "d /var/log/remote 0750 root adm -"
        "d /var/log/remote/OPNsense.internal 0750 root adm -"
        "d /root/.ssh      0700 root root -"
        "d /usr/local/bin  0755 root root -"
        "L+ /usr/local/bin/wazuh-github-ci-status - - - - ${pkgs.writeShellScript "wazuh-github-ci-status" (builtins.readFile ./wazuh-github-ci-status.sh)}"
        "L+ /usr/local/bin/wazuh-tailscale-health - - - - ${pkgs.writeShellScript "wazuh-tailscale-health" (builtins.readFile ./wazuh-tailscale-health.sh)}"
      ];

      # Borg backup to nas01
      # Passphrase comes from bitwarden-scott.nix -> /run/bitwarden-secrets/borg_passphrase
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/log01";
        paths = [ "/home" "/var/log" ];
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519_legacy";
      };

      # Logrotate — 1 month retention for remote syslog collection
      services.logrotate.settings.remote-logs = {
        files = "/var/log/remote/*/*.log";
        frequency = "daily";
        # 7 days, not 30 — nas01's pool/rsyslog dataset (quota=1.5T) is the
        # long-term copy now; this is just a short resilience buffer for
        # when nas01 is briefly unreachable. maxsize: rotate immediately on
        # a volume burst too, not just the daily schedule — unbounded
        # growth between scheduled rotations is exactly how log01's root
        # disk hit 100% on 2026-10-25 in the first place.
        rotate = 7;
        maxsize = "500M";
        compress = true;
        dateext = true;
        missingok = true;
        notifempty = true;
        sharedscripts = true;
        postrotate = "systemctl kill -s HUP syslog.service 2>/dev/null || true";
      };

      # Logrotate for the base local syslog outputs — these had no rotation
      # at all, which is how /var/log/messages grew to 22G (OpenSearch
      # repeatedly logging write-failure stack traces as the disk filled,
      # a feedback loop) and took the root filesystem to 100% full on
      # 2026-10-25. The service unit is "syslog.service" on NixOS, not
      # "rsyslog.service" — the postrotate hook above had been silently
      # no-op'ing on the wrong unit name this whole time too.
      services.logrotate.settings.local-syslog = {
        files = "/var/log/messages /var/log/warn";
        frequency = "daily";
        rotate = 14;
        maxsize = "500M";
        compress = true;
        dateext = true;
        missingok = true;
        notifempty = true;
        sharedscripts = true;
        postrotate = "systemctl kill -s HUP syslog.service 2>/dev/null || true";
      };

      system = {
        stateVersion = "25.11";
        nixos.label = "log01";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
