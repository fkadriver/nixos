{ inputs, ... }@flakeContext:
# MacBook Air 7,2 back on NixOS (XFCE), restored 2026-11-20 from
# archive/hosts/airbook after a forced macOS Tahoe upgrade. The nix-darwin
# config (hosts/airbook-darwin) is kept alongside in case it goes back.
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      ./bluetooth.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-xfce  # pulls in daily-driver
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.wireless
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.fwupd
    ];
    config = {
      networking.hostName = "airbook";

      # Partitioned by diskoConfigurations.airbook (flake.nix); mounts are in
      # hardware.nix. The archived config hardcoded /dev/nvme0n1p* instead.

      # First boot generates the sops age key; then add its public key to
      # .sops.yaml and `sops updatekeys secrets/secrets.yaml` so bitwarden
      # (and everything fetched from it) can decrypt.
      sops.age.generateKey = true;

      # Borg backup to nas01 — fresh repo, separate from airbook-darwin's.
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/airbook";
        encryption.passphraseFile = "/run/bitwarden-secrets/borg_passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519_legacy";
      };

      system.stateVersion = "26.11";
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
}
