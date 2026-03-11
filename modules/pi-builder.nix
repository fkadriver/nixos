{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {

  config = {
    # Enable aarch64 cross-compilation via QEMU binfmt emulation.
    # Allows this x86_64 machine to build NixOS configs for Raspberry Pi (aarch64-linux).
    # Usage from latitude: nixos-rebuild switch --flake .#pihole02 \
    #   --target-host scott@pihole02 --build-host localhost
    # Usage from any machine: nixos-rebuild ... --build-host vm01
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    # Expose the binfmt QEMU wrapper and /run/binfmt into nix build sandboxes
    # so aarch64 derivations can execute via QEMU during sandboxed x86_64 builds
    nix.settings.extra-sandbox-paths = [ "/run/binfmt" ];

    # Tell nix this machine can build aarch64 derivations via QEMU binfmt emulation
    nix.settings.extra-platforms = [ "aarch64-linux" ];
  };
}
