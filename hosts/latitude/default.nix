{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/latitude";
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
      };

      # Enable aarch64 emulation so the latitude can build Pi configs and SD images
      # Build: nix build .#nixosConfigurations.pihole02.config.system.build.sdImage
      # Deploy: nixos-rebuild switch --flake .#pihole02 --target-host scott@192.168.10.11
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Expose the binfmt QEMU wrapper into nix build sandboxes so aarch64
      # derivations can be executed via QEMU during sandboxed builds on x86_64
      nix.settings.extra-sandbox-paths = [ "/run/binfmt" ];

      # Tell nix this machine can build aarch64 derivations via QEMU binfmt emulation
      nix.settings.extra-platforms = [ "aarch64-linux" ];

      # Allow nixos-rebuild --build-host localhost to build Pi configs locally over SSH loopback.
      # Without this, --target-host delegates the build to the Pi (which lacks sandbox support).
      services.openssh = {
        enable = true;
        listenAddresses = [{ addr = "127.0.0.1"; port = 22; }];
        settings.PasswordAuthentication = false;
      };

      system = {
        stateVersion = "25.11";
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
