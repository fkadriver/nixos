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

      # Ensure remote log directory and root SSH dir exist with correct permissions
      systemd.tmpfiles.rules = [
        "d /var/log/remote 0750 root adm -"
        "d /root/.ssh      0700 root root -"
      ];

      # Borg backup to nas01
      # Passphrase comes from bitwarden-scott.nix -> /run/bitwarden-secrets/borg_passphrase
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18t_3/borg/repos/log01";
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
