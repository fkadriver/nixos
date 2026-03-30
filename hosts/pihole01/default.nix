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
        hostName = "pihole01";
        useDHCP = false;
        interfaces.eth0.ipv4.addresses = [{
          address = "192.168.10.10";
          prefixLength = 24;
        }];
        defaultGateway = "192.168.10.1";
      };

      # Pin FTL reply addresses to this host's static IP
      services.pihole-ftl.settings.dns.reply = {
        host     = { force4 = true; IPv4 = "192.168.10.10"; };
        blocking = { force4 = true; IPv4 = "192.168.10.10"; };
      };

      # Headless managed device — no sudo password needed for wheel
      security.sudo.wheelNeedsPassword = false;

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
    # raspberry-pi-nix modules imported here where inputs is accessible
    inputs.raspberry-pi-nix.nixosModules.raspberry-pi
    inputs.raspberry-pi-nix.nixosModules.sd-image
    {
      # Cross-compile from x86_64 build host to aarch64 Pi
      nixpkgs.hostPlatform.system = "aarch64-linux";
      nixpkgs.buildPlatform.system = "x86_64-linux";
    }
  ];
}
