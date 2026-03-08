{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.pihole
      inputs.self.nixosModules.user-scott
    ];

    config = {
      networking = {
        hostName = "pihole02";
        useDHCP = false;
        interfaces.eth0.ipv4.addresses = [{
          address = "192.168.10.11";
          prefixLength = 24;
        }];
        defaultGateway = "192.168.10.1";
      };

      # Pin FTL reply addresses to this host's static IP
      services.pihole-ftl.settings.dns.reply = {
        host     = { force4 = true; IPv4 = "192.168.10.11"; };
        blocking = { force4 = true; IPv4 = "192.168.10.11"; };
      };

      system = {
        stateVersion = "25.11";
        nixos.label = "pihole02";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
    # nixos-hardware Pi 3B support (handles kernel, bootloader, kernel modules)
    # raspberry-pi-nix does not support BCM2837 (Pi 3)
    inputs.nixos-hardware.nixosModules.raspberry-pi-3
    {
      # Cross-compile from x86_64 build host to aarch64 Pi
      nixpkgs.hostPlatform.system = "aarch64-linux";
      nixpkgs.buildPlatform.system = "x86_64-linux";
    }
  ];
}
