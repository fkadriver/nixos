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

      # scripts/deploy-piholes.sh cross-builds on vm01 and pushes the result
      # unattended — no human in the loop to type a sudo password.
      security.sudo.wheelNeedsPassword = false;

      # Kernel version lock — Pi 4B (nixos-raspberrypi vendor kernel, served
      # prebuilt by nixos-raspberrypi.cachix.org; see the flake input comment)
      # Update alongside LOCKED_KERNEL_VERSIONS in scripts/deploy-piholes.sh
      pihole.lockedKernelVersion = "6.18.59-unstable_20261026";

      system = {
        stateVersion = "25.11";
        nixos.label = "pihole01";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  # nixos-raspberrypi's modules take the flake itself as a module argument.
  specialArgs = { nixos-raspberrypi = inputs.nixos-raspberrypi; };
  modules = [
    nixosModule
    # Pi 4B support: vendor kernel + firmware from nixos-raspberrypi's own
    # (cached) package set, bootloader, config.txt generation. Its
    # trusted-nix-caches module is not imported: it would replace the Pi's
    # default substituters, and the Pi never builds anything itself — the
    # cache matters on the build hosts (see modules/pi-builder.nix).
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.sd-image
    {
      # Cross-compile from x86_64 build host to aarch64 Pi. The kernel is
      # unaffected: it comes from nixos-raspberrypi.packages.aarch64-linux.
      nixpkgs.hostPlatform.system = "aarch64-linux";
      nixpkgs.buildPlatform.system = "x86_64-linux";
    }
  ];
}
