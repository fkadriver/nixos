{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.disko.nixosModules.disko
      inputs.self.nixosModules.disko-config
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.user-scott
    ];

    config = {
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

          # Route remote messages to per-host directories
          if $fromhost-ip != "127.0.0.1" then {
            action(type="omfile" dynaFile="RemoteHost")
            stop
          }
        '';
      };

      # Ensure remote log directory exists with correct permissions
      systemd.tmpfiles.rules = [
        "d /var/log/remote 0750 root root -"
      ];

      # Borg backup to nas01
      # Passphrase comes from bitwarden-scott.nix -> /run/bitwarden-secrets/borg_passphrase
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18t_3/borg/repos/log01";
        paths = [ "/home" "/var/log/remote" ];
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519_legacy";
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
