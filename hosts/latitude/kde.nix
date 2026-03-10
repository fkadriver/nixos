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
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      # Enable aarch64 emulation for building Pi configs and SD images
      # Deploy: nixos-rebuild switch --flake .#pihole02 --target-host scott@192.168.10.11
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
      nix.settings.extra-sandbox-paths = [ "/run/binfmt" ];
      nix.settings.extra-platforms = [ "aarch64-linux" ];

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
