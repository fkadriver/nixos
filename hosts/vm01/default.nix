{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware-configuration.nix
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.borg-backup
      inputs.self.nixosModules.wireless
      inputs.self.nixosModules.user-scott
    ];

    config = {
      # Home-manager configuration
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      # Boot loader configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking = {
        hostName = "vm01";
        networkmanager.enable = true;
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
