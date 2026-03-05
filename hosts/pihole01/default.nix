{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.pihole
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.user-scott
    ];

    config = {
      networking = {
        hostName = "pihole01";
        useDHCP = false;
        interfaces.eth0.ipv4.addresses = [{
          address = "192.168.10.10";
          prefixLength = 24;
        }];
        defaultGateway = "192.168.10.1";  # Adjust to your gateway
      };

      # Borg backup — backs up Pi-hole state (gravity.db, query logs)
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/pihole01";
        paths = [ "/var/lib/pihole" "/home" ];
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
      };

      system = {
        stateVersion = "25.11";
        nixos.label = "pihole01";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
    {
      # Cross-compile from x86_64 build host to aarch64 Pi
      # Build host needs: boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
      nixpkgs.hostPlatform.system = "aarch64-linux";
      nixpkgs.buildPlatform.system = "x86_64-linux";
    }
  ];
}
