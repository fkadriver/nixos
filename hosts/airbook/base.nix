# Shared airbook config, imported by both desktop variants:
#   default.nix -> airbook     (XFCE + Plank dock)
#   kde.nix     -> airbook-kde (Plasma 6, as on latitude)
# Both keep hostName "airbook", so Tailscale, Syncthing, Borg and the
# distributed-builds host key pin are the same whichever one is booted.
# The desktop module (laptop-xfce / laptop-kde) also pulls in daily-driver.
{ inputs, config, lib, pkgs, ... }: {
  imports = [
    ./hardware.nix
    ./syncthing.nix
    ./bluetooth.nix
    inputs.self.nixosModules.common
    inputs.self.nixosModules.multi-monitor
    inputs.self.nixosModules.wireless
    inputs.self.nixosModules.user-scott
    inputs.self.nixosModules.fwupd
    # Peer binary-cache substitution + build offload to latitude/vm01, so
    # fleet-built paths (e.g. orca-slicer) are fetched, not rebuilt here.
    inputs.self.nixosModules.distributed-builds
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

    # Same as latitude (the other laptop): sshd on loopback only, key auth.
    # Remote access is via Tailscale SSH; nothing is exposed on whatever
    # Wi-Fi the laptop is on. Running sshd also gives the host a stable
    # /etc/ssh key, which Tailscale SSH then presents and
    # distributed-builds.nix pins.
    services.openssh = {
      enable = true;
      listenAddresses = [{ addr = "127.0.0.1"; port = 22; }];
      settings.PasswordAuthentication = false;
    };

    # MTGA is the Heroic/Epic app "stargazer". Heroic only makes a ~/Desktop
    # shortcut for it, not a menu entry, so declare one. Its icon is the one
    # Heroic caches at install time (user state; the launcher shows a generic icon if
    # it's missing). On this GPU MTGA also needs PROTON_USE_WINED3D=1 in its
    # Heroic settings: GE-Proton's DXVK needs Vulkan 1.3, which Broadwell's
    # HD 6000 lacks, so the game crashes at startup without it.
    environment.systemPackages = [ (pkgs.makeDesktopItem {
      name = "mtga";
      desktopName = "Magic: The Gathering Arena";
      exec = ''heroic --no-gui "heroic://launch?appName=stargazer&runner=legendary"'';
      icon = "/home/scott/.config/heroic/icons/stargazer.jpg";
      categories = [ "Game" ];
    }) ];

    system.stateVersion = "26.11";
  };
}
