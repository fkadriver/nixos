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
      # NOTE: do not add a forward action that all messages pass through unless it
      # has its own bounded queue with discard — a dead target (like the retired
      # Splunk host) backpressures the main queue, stalls imtcp reads, and wedges
      # every sender's forward queue fleet-wide (Jun-Jul 2026 outage).
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

          # For Pi-hole DNS logs: rsyslog puts the full payload into %syslogtag%
          # and leaves %msg% empty because the imfile Tag has no trailing colon.
          # %syslogtag% = "pihole-dns Jul 15 HH:MM:SS dnsmasq[PID]: ..."
          # Content starts at char 12 (after "pihole-dns" [10] + space [1] = 11).
          # The literal "pihole-dns:" injects the colon Wazuh's pre-decoder needs.
          template(name="PiholeSyslog" type="string"
            string="ST=[%syslogtag%] MSG=[%msg%] RAW=[%rawmsg-after-pri%]\n")

          # For all other remote programs with properly colon-terminated syslogtags,
          # content is in %msg% as usual.
          template(name="WazuhSyslog" type="string"
            string="%TIMESTAMP% %HOSTNAME% %PROGRAMNAME%:%msg:::sp-if-no-1st-sp,drop-last-lf%\n")

          $FileOwner root
          $FileGroup adm
          $FileCreateMode 0640
          $DirOwner root
          $DirGroup adm
          $DirCreateMode 0750

          # Pi-hole rule must come first so its messages are consumed before the
          # general remote rule runs.
          :programname, isequal, "pihole-dns"   ?RemoteHost;PiholeSyslog
          :programname, isequal, "pihole-dns"   ~
          :fromhost-ip, !isequal, "127.0.0.1"   ?RemoteHost;WazuhSyslog
          :fromhost-ip, !isequal, "127.0.0.1"   ~
        '';
      };

      # Wazuh Docker Compose stack — all secrets fetched from Bitwarden at boot
      services.bitwarden.secrets.wazuh_ts_authkey = {
        name = "wazuh_ts_authkey";
        itemId = "c6077703-deef-4684-bb9d-b48601451e64";
        field = "tskey";
        mode = "0400";
      };
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

              # .env — Tailscale auth key
              printf 'TS_AUTHKEY=%s\n' "$(cat /run/bitwarden-secrets/wazuh_ts_authkey)" \
                > "$REPO/.env"
              chmod 600 "$REPO/.env"

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
