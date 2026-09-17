{ inputs, ... }@flakeContext:
let
  # Logs container state/restart-count for unifi-controller and unifi-db so
  # Wazuh can alert if the stack goes down or starts restart-looping.
  unifiDockerStatusScript = pkgs: pkgs.writeShellScript "unifi-docker-status" ''
    LOG=/var/log/unifi-docker-status.log
    for name in unifi-controller unifi-db; do
      state=$(${pkgs.docker}/bin/docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
      if [ -z "$state" ]; then
        echo "$(date '+%b %d %H:%M:%S') vm01 unifi-docker-status: container=$name status=MISSING" >> "$LOG"
        continue
      fi
      restarts=$(${pkgs.docker}/bin/docker inspect -f '{{.RestartCount}}' "$name" 2>/dev/null)
      if [ "$state" != "running" ]; then
        echo "$(date '+%b %d %H:%M:%S') vm01 unifi-docker-status: container=$name status=DOWN state=$state restarts=$restarts" >> "$LOG"
      else
        echo "$(date '+%b %d %H:%M:%S') vm01 unifi-docker-status: container=$name status=OK state=$state restarts=$restarts" >> "$LOG"
      fi
    done
  '';

  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware-configuration.nix
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.tsauth
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.vscode-server
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.pi-builder
      inputs.self.nixosModules.distributed-builds
      inputs.self.nixosModules.deploy-pihole
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.smart-monitor
      inputs.self.nixosModules.disk-usage-monitor
      inputs.self.nixosModules.fwupd
    ];

    config = {
      # Home-manager configuration
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      # Boot loader configuration
      boot.loader.systemd-boot.enable = true;
      # boot.loader.systemd-boot.configurationLimit = 2;
      boot.loader.efi.canTouchEfiVariables = true;

      # Allow nixos-rebuild --build-host localhost to build Pi configs locally over SSH loopback.
      services.openssh = {
        enable = true;
        listenAddresses = [{ addr = "127.0.0.1"; port = 22; }];
        settings.PasswordAuthentication = false;
      };

      # Root SSH key for --build-host localhost
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKQAbdUJryCwtrqb9DvuMFZYvYrFj795KhiKTk0NEyC root@vm01"
      ];

      # Tell root's SSH to use the build key when connecting to localhost
      programs.ssh.extraConfig = ''
        Host localhost
          IdentityFile /root/.ssh/id_ed25519_build
          StrictHostKeyChecking no
      '';

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
        extraLocalFiles = [
          { location = "/var/log/unifi-docker-status.log"; logFormat = "syslog"; }
          { location = "/home/scott/git/unifi_controller/unifi-config/logs/server.log"; logFormat = "syslog"; }
        ];
      };

      # Force fresh Wazuh install by removing stale ossec.conf from the
      # pre-migration era. The installScript guard (ConditionPathExists=!ossec.conf)
      # will re-extract from the 4.14.5 .deb and patch the manager address.
      # client.keys is also wiped so re-enrollment triggers cleanly.
      # Marker prevents this from running on every rebuild.
      system.activationScripts.wazuhFreshInstall = lib.stringAfter [ "users" "setupSecrets" ] ''
        CONF=/var/ossec/etc/ossec.conf
        MARKER=/var/ossec/etc/.fresh-install-4145
        if [ -f "$CONF" ] && [ ! -f "$MARKER" ]; then
          echo "Forcing Wazuh fresh install for 4.14.5 agent config..."
          # Stop all wazuh daemons first
          /run/current-system/sw/bin/systemctl stop wazuh-agent.service 2>/dev/null || true
          ${pkgs.procps}/bin/pkill -f 'wazuh-' 2>/dev/null || true
          sleep 1
          # Remove stale ossec.conf and client.keys to trigger clean reinstall+enroll
          rm -f "$CONF" /var/ossec/etc/client.keys /var/ossec/etc/.reenrolled-log01
          touch "$MARKER"
          # Explicitly restart the install and enroll services — RemainAfterExit keeps
          # them "done" even after the files are removed. After install completes,
          # restart enroll so a fresh client.keys is registered with the manager.
          /run/current-system/sw/bin/systemctl restart wazuh-agent-install.service || true
          /run/current-system/sw/bin/systemctl restart wazuh-agent-enroll.service || true
        fi
      '';

      # Re-trigger enrollment whenever client.keys is empty (e.g. after fresh install).
      # systemctl restart is synchronous for oneshot services — the agent restart
      # below sees the newly-written client.keys.
      system.activationScripts.wazuhReEnroll = lib.stringAfter [ "users" "setupSecrets" "wazuhFreshInstall" ] ''
        if [ ! -s /var/ossec/etc/client.keys ] 2>/dev/null; then
          echo "Restarting Wazuh enrollment (client.keys is empty)..."
          /run/current-system/sw/bin/systemctl restart wazuh-agent-enroll.service || true
          echo "Restarting Wazuh agent to pick up new client.keys..."
          /run/current-system/sw/bin/systemctl restart wazuh-agent.service || true
        fi
      '';

      # Add scott to wazuh group so ossec.log is readable for diagnostics
      users.users.scott.extraGroups = [ "wazuh" ];

      # Fallback DNS if both piholes are unreachable (build host must resolve to deploy piholes)
      services.resolved.settings.Resolve.FallbackDNS = [ "1.1.1.3" ];

      networking = {
        hostName = "vm01";
        networkmanager.enable = true;
        firewall = {
          allowedTCPPorts = [ 8080 8443 8880 8843 6789 ];
          allowedUDPPorts = [ 3478 10001 1900 ];
        };
      };

# Dell Latitude E7270 - Service Tag: 7NYTSF2

      # Immich library/uploads live on nas01 (/pool/photos, ZFS raidz1),
      # mounted here over NFS via Tailscale — replaces the old local
      # /mnt/immich USB drive (removed: it was failing and USB besides).
      # Postgres stays local (under the compose checkout, see immich-docker
      # below) since Postgres doesn't tolerate NFS-backed data directories.
      # No dedicated immich system user needed here — the compose checkout
      # lives under scott's home like unifi_controller below, and the actual
      # immich-server container process runs as PUID/PGID 991:989 (nas01's
      # immich uid/gid, which owns the exported files) regardless of which
      # host user invokes `docker compose`.
      fileSystems."/mnt/nas01/immich-library" = {
        device = "nas01.warthog-royal.ts.net:/pool/photos";
        fsType = "nfs";
        options = [
          "_netdev"
          "nofail"
          "hard"
          "timeo=30"
          "retrans=3"
          "x-systemd.requires=tailscaled.service"
          "x-systemd.after=tailscaled.service"
          "x-systemd.mount-timeout=30"
        ];
      };

      # Immich Docker Compose stack. Repo cloned manually as scott, same
      # convention as unifi_controller below:
      #   git clone git@github.com:fkadriver/immich-app.git ~/git/immich-app
      # .env (gitignored upstream, lives only on this host — never commit the
      # Tailscale AUTH_KEY or DB creds) needs UPLOAD_LOCATION=/mnt/nas01/immich-library,
      # DB_DATA_LOCATION=./postgres-vm01, PUID=991, PGID=989.
      systemd.services.immich-docker = {
        description = "Immich Docker Compose Stack";
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/scott/git/immich-app";
          RequiresMountsFor = "/mnt/nas01/immich-library";
          ExecStart = "${pkgs.docker}/bin/docker compose up -d";
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Unifi Docker Compose stack
      systemd.services.unifi-docker = {
        description = "Unifi Docker Compose Stack";
        wantedBy = [ "multi-user.target" ];
        after = [ "bitwarden-secrets-sync.service" "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "bitwarden-secrets-sync.service" "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "/home/scott/git/unifi_controller";
          ExecStart = pkgs.writeShellScript "unifi-docker-start" ''
            set -euo pipefail
            export TS_AUTHKEY=$(cat /run/bitwarden-secrets/container_ts_authkey)
            exec ${pkgs.docker}/bin/docker compose up -d
          '';
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Container health check for Wazuh (see wazuh-agent extraLocalFiles above)
      systemd.services.unifi-docker-status = {
        description = "Log UniFi docker container health for Wazuh";
        after = [ "unifi-docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = unifiDockerStatusScript pkgs;
        };
      };
      systemd.timers.unifi-docker-status = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "10min";
          Persistent = true;
        };
      };

      # Borg backup to nas01
      # Passphrase comes from bitwarden-scott.nix -> /run/bitwarden-secrets/borg_passphrase
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/vm01";
        # /mnt/immich (old USB drive) removed; immich's Postgres data now
        # lives under /home/scott/git/immich-app/postgres-vm01, already
        # covered by /home.
        paths = [ "/home" ];
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519_legacy";
      };

      system = {
        stateVersion = "25.11";
        nixos.label = "vm01";
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
