{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware-configuration.nix
      inputs.disko.nixosModules.disko
      inputs.self.nixosModules.disko-config
      inputs.self.nixosModules.common
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.wireless
      inputs.self.nixosModules.user-scott
    ];

    config = {
      networking = {
        hostName = "vm01";
        networkmanager.enable = true;
      };

      # Dell Latitude E7270 - Service Tag: 7NYTSF2

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/vm01";
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
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
