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

  # Every fleet host that peer-shares locally-built store paths via binary-
  # cache substitution (distinct from the job-offloading above, which stays
  # scoped to latitude/vm01 — substitution just answers "has anyone already
  # built this path?", no speedFactor/maxJobs tuning needed). Piholes are
  # excluded: they're aarch64 appliances built via explicit --build-host
  # cross-compilation (scripts/deploy-piholes.sh), not daemon-managed peers.
  #
  # configName must match config.networking.hostName on that host; sshHost
  # is the Tailscale-reachable name used to actually dial it — OTworkstation
  # is capitalized in its hostName but not in its Tailscale/ssh name.
  peers = [
    { configName = "latitude"; sshHost = "latitude"; }
    { configName = "vm01"; sshHost = "vm01"; }
    { configName = "nas01"; sshHost = "nas01"; }
    { configName = "log01"; sshHost = "log01"; }
    { configName = "OTworkstation"; sshHost = "otworkstation"; }
  ];
  otherPeers = builtins.filter (p: p.configName != hostname) peers;
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

  # SSH config for cross-machine builds and peer substitution (applies
  # system-wide, used by root/the nix daemon).
  programs.ssh.extraConfig = lib.concatMapStrings (p: ''
    Host ${p.sshHost}
      IdentityFile /home/scott/.ssh/id_ed25519_legacy
      StrictHostKeyChecking no
  '') otherPeers;

  # Mutual binary-cache substitution across the whole fleet (piholes
  # excluded): whatever any host has already built — the aarch64 pihole
  # closures (hours of QEMU cross-compilation), or a package rebuilt
  # fleet-wide for a CVE fix before Hydra's cache catches up — every other
  # host can fetch instead of rebuilding. All hosts sign locally-built paths
  # with the same shared key so any peer can verify paths built by any
  # other, without weakening signature checking against the real
  # substituters (cache.nixos.org, cachix) the way require-sigs=false would.
  sops.age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
  sops.secrets."nix_cache/signing_key" = {
    sopsFile = ../secrets/secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  nix.settings = {
    secret-key-files = [ config.sops.secrets."nix_cache/signing_key".path ];
    extra-substituters = map (p: "ssh-ng://scott@${p.sshHost}") otherPeers;
    extra-trusted-public-keys = [
      "jen-acres-builders:rYBoDlCKPnKYZe4K90CFBGy0QTmhuTBChyGzYxw1Nzs="
    ];
  };
}
