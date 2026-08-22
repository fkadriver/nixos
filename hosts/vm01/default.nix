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

      # Immich service user
      users.users.immich = {
        isSystemUser = true;
        group = "immich";
        home = "/opt/immich";
        createHome = true;
        shell = pkgs.bash;
        extraGroups = [ "docker" ];
      };
      users.groups.immich = {};

      # External 1TB drive for Immich
      fileSystems."/mnt/immich" = {
        device = "/dev/disk/by-uuid/f2cd320d-fe0a-474f-8662-f6fcc4171a3e";
        fsType = "ext4";
        options = [ "nofail" "x-systemd.device-timeout=5" ];
      };

      # Set immich as owner of the mount point after mount
      systemd.services.immich-mount-permissions = {
        description = "Set ownership of /mnt/immich";
        after = [ "mnt-immich.mount" ];
        requires = [ "mnt-immich.mount" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/chown immich:immich /mnt/immich";
          RemainAfterExit = true;
        };
      };

      # Deploy GitHub SSH key and config for the immich service user.
      # The key is fetched from Bitwarden into scott's ~/.ssh during the
      # bitwarden-ssh-keys activation step; we copy it here afterwards.
      system.activationScripts.immichSshGithub = lib.stringAfter [ "bitwarden-ssh-keys" "users" ] ''
        SSH_DIR=/opt/immich/.ssh
        SRC_KEY=/home/scott/.ssh/id_ed25519_github

        if [ -f "$SRC_KEY" ]; then
          mkdir -p "$SSH_DIR"
          chmod 700 "$SSH_DIR"
          chown immich:immich "$SSH_DIR"

          cp "$SRC_KEY" "$SSH_DIR/id_ed25519_github"
          chmod 600 "$SSH_DIR/id_ed25519_github"
          chown immich:immich "$SSH_DIR/id_ed25519_github"

          cat > "$SSH_DIR/config" << 'EOF'
Host github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
          chmod 600 "$SSH_DIR/config"
          chown immich:immich "$SSH_DIR/config"
        else
          echo "Warning: $SRC_KEY not found — immich GitHub SSH key not installed" >&2
        fi
      '';

      # Disable starship for immich user
      system.activationScripts.immichBashrc = ''
        mkdir -p /opt/immich
        cat > /opt/immich/.bashrc << 'EOF'
# Minimal bashrc for immich service user - no starship
export PS1='[\u@\h \W]\$ '
EOF
        chown immich:immich /opt/immich/.bashrc
      '';

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
        paths = [ "/home" "/mnt/immich" ];
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
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
