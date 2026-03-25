{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  hostname = config.networking.hostName;

  # Each machine's capabilities as a remote builder.
  # Both already have aarch64 binfmt emulation via pi-builder.nix.
  latitudeMachine = {
    hostName = "latitude";
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 4;
    speedFactor = 2;  # faster CPU than vm01
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    sshUser = "root";
    sshKey = "/root/.ssh/id_ed25519_build";
  };

  vm01Machine = {
    hostName = "vm01";
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 2;
    speedFactor = 1;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    sshUser = "root";
    sshKey = "/root/.ssh/id_ed25519_build";
  };
in {
  # Enable distributing derivations to remote build machines.
  # When one machine is the --build-host for a pihole deploy, it farms out
  # independent derivations to the other, building in parallel.
  # The linux-rpi kernel is a single derivation and still builds on one machine,
  # but all other aarch64 packages can build concurrently across both.
  nix.distributedBuilds = true;

  # Each host lists the other as a build machine (excludes itself).
  nix.buildMachines =
    lib.optionals (hostname != "latitude") [ latitudeMachine ] ++
    lib.optionals (hostname != "vm01")     [ vm01Machine ];

  # Root SSH config for cross-machine builds.
  # Uses the same id_ed25519_build key that is already in each machine's
  # root authorizedKeys (set up for --build-host localhost loopback).
  programs.ssh.extraConfig = lib.optionalString (hostname != "latitude") ''
    Host latitude
      IdentityFile /root/.ssh/id_ed25519_build
      StrictHostKeyChecking no
  '' + lib.optionalString (hostname != "vm01") ''
    Host vm01
      IdentityFile /root/.ssh/id_ed25519_build
      StrictHostKeyChecking no
  '';
}
