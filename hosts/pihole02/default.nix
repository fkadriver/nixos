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

      # Headless managed device — no sudo password needed for wheel
      security.sudo.wheelNeedsPassword = false;

      # Kernel version lock — Pi 3B (nixos-hardware kernel)
      # Update alongside LOCKED_KERNEL_VERSIONS in scripts/deploy-piholes.sh
      pihole.lockedKernelVersion = "6.18.34-stable_20260609";

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
      # Target platform is aarch64 (Raspberry Pi 3B).
      # buildPlatform is intentionally omitted — it auto-detects from the build host.
      # On x86_64 (latitude with binfmt aarch64 emulation): cross-compiles.
      # On the Pi itself (--target-host deploys): builds natively.
      nixpkgs.hostPlatform.system = "aarch64-linux";
    }
  ];
}
