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
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Distributed builds: only enabled on vm01.
  # latitude must not offload its own local builds to vm01 — only pihole deploys
  # use both machines, and those are driven explicitly via --build-host, not the daemon.
  nix.distributedBuilds = hostname != "latitude";

  # Each host lists the other as a build machine (excludes itself).
  # latitude still has vm01 in its list so --build-host latitude can farm out to vm01
  # when building pihole configs, but the daemon won't use it for local builds.
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

  # Mutual binary-cache substitution: whatever either machine has already built
  # (e.g. the aarch64 pihole closures — hours of QEMU cross-compilation), the
  # other can fetch instead of rebuilding. Both sign locally-built paths with
  # the same shared key so either side can verify paths built by the other,
  # without weakening signature checking against the real substituters
  # (cache.nixos.org, cachix) the way require-sigs=false would.
  sops.age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
  sops.secrets."nix_cache/signing_key" = {
    sopsFile = ../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  nix.settings = {
    secret-key-files = [ config.sops.secrets."nix_cache/signing_key".path ];
    extra-substituters =
      lib.optionals (hostname != "latitude") [ "ssh-ng://scott@latitude" ] ++
      lib.optionals (hostname != "vm01")     [ "ssh-ng://scott@vm01" ];
    extra-trusted-public-keys = [
      "jen-acres-builders:rYBoDlCKPnKYZe4K90CFBGy0QTmhuTBChyGzYxw1Nzs="
    ];
  };
}
