{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.vscode-server
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.user-scott
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
    ];

    config = {
      # Do not forward logs back to log01 (this IS log01)
      logging.forwardToLog01 = false;

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

      # Headless managed device — no sudo password needed for wheel
      security.sudo.wheelNeedsPassword = false;

      # rsyslog: receive syslog from network devices on UDP/TCP 514
      # Logs stored at /var/log/remote/<hostname>/<program>.log
      # All logs (local + remote) forwarded to Splunk over TCP with disk queue
      services.rsyslogd = {
        enable = true;
        extraConfig = ''
          # Load input modules for remote syslog reception
          module(load="imudp")
          module(load="imtcp")

          input(type="imudp" port="514")
          input(type="imtcp" port="514")

          # Per-host log file template
          template(name="RemoteHost" type="string"
            string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")

          # Forward ALL messages (log01 local + all remote devices) to Splunk.
          # Must appear before the stop below so remote messages are also captured.
          action(type="omfwd"
            target="splunk.warthog-royal.ts.net"
            port="5514"
            protocol="tcp"
            queue.type="LinkedList"
            queue.filename="splunkfwd"
            queue.maxdiskspace="500m"
            queue.saveonshutdown="on"
            action.resumeRetryCount="-1"
            action.resumeInterval="30")

          # Route remote messages to per-host directories.
          # Permissions are set explicitly here — global() is not used because
          # it must appear before all other config statements, but extraConfig
          # is appended after the NixOS-generated base config.
          if $fromhost-ip != "127.0.0.1" then {
            action(type="omfile"
              dynaFile="RemoteHost"
              fileCreateMode="0640"
              fileOwner="root"
              fileGroup="adm"
              dirCreateMode="0750"
              dirOwner="root"
              dirGroup="adm")
            stop
          }
        '';
      };

      # Wazuh Docker Compose stack — TS auth key fetched from Bitwarden at boot
      services.bitwarden.secrets.wazuh_ts_authkey = {
        name = "wazuh_ts_authkey";
        itemId = "c6077703-deef-4684-bb9d-b48601451e64";
        field = "tskey";
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
          ExecStartPre = pkgs.writeShellScript "wazuh-write-secrets" ''
            set -euo pipefail
            printf 'TS_AUTHKEY=%s\n' "$(cat /run/bitwarden-secrets/wazuh_ts_authkey)" \
              > /home/scott/git/wazuh-tailscale/.env
            chmod 600 /home/scott/git/wazuh-tailscale/.env
            rm -rf /home/scott/git/wazuh-tailscale/config/wazuh_cluster/authd.pass
            cp /run/bitwarden-secrets/wazuh_agent_enrollment_password \
              /home/scott/git/wazuh-tailscale/config/wazuh_cluster/authd.pass
            chmod 600 /home/scott/git/wazuh-tailscale/config/wazuh_cluster/authd.pass
          '';
          ExecStart = "${pkgs.docker}/bin/docker compose up -d";
          ExecStop = "${pkgs.docker}/bin/docker compose down";
        };
      };

      # Ensure remote log directory and root SSH dir exist with correct permissions
      systemd.tmpfiles.rules = [
        "d /var/log/remote 0750 root adm -"
        "d /root/.ssh      0700 root root -"
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
        rotate = 30;
        compress = true;
        dateext = true;
        missingok = true;
        notifempty = true;
        sharedscripts = true;
        postrotate = "systemctl kill -s HUP rsyslog.service 2>/dev/null || true";
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
