{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  hostname = config.networking.hostName;

  # Each machine's capabilities as a remote builder.
  # Both already have aarch64 binfmt emulation via pi-builder.nix.
  #
  # sshUser = "scott": Tailscale ACLs block root SSH; scott is a trusted-user
  # in nix.settings so the nix daemon accepts builds from him.
  # sshKey = id_ed25519_legacy: deployed to every host via bitwarden-scott.nix
  # and already present in user-scott.nix openssh.authorizedKeys — no extra
  # key setup needed.
  latitudeMachine = {
    hostName = "latitude";
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 4;
    speedFactor = 2;  # faster CPU than vm01
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    sshUser = "scott";
    sshKey = "/home/scott/.ssh/id_ed25519_legacy";
  };

  vm01Machine = {
    hostName = "vm01";
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 2;
    speedFactor = 1;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    sshUser = "scott";
    sshKey = "/home/scott/.ssh/id_ed25519_legacy";
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

  # SSH config for cross-machine builds (applies system-wide, used by root/nix daemon).
  programs.ssh.extraConfig = lib.optionalString (hostname != "latitude") ''
    Host latitude
      IdentityFile /home/scott/.ssh/id_ed25519_legacy
      StrictHostKeyChecking no
  '' + lib.optionalString (hostname != "vm01") ''
    Host vm01
      IdentityFile /home/scott/.ssh/id_ed25519_legacy
      StrictHostKeyChecking no
  '';
}
