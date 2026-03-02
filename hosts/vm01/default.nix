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
      # boot.loader.systemd-boot.configurationLimit = 2;
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

      # External 1TB drive for Immich
      fileSystems."/mnt/immich" = {
        device = "/dev/disk/by-uuid/f2cd320d-fe0a-474f-8662-f6fcc4171a3e";
        fsType = "ext4";
        options = [ "nofail" "x-systemd.device-timeout=5" ];
      };

      # Set immich as owner of the mount point
      systemd.tmpfiles.rules = [
        "d /mnt/immich 0755 immich immich -"
      ];

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
