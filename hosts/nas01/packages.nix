{ inputs, ... }:

# Nix-managed packages for nas01 (Ubuntu 25.10)
# Install/update with: sudo nix profile install --profile /nix/var/nix/profiles/nas01 .#nas01-env
#
# NOTE: The following are intentionally managed by apt, not Nix:
#   - zfsutils-linux  (kernel module must match Ubuntu kernel via DKMS)
#   - nfs-kernel-server (kernel module integration)

let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
in
pkgs.buildEnv {
  name = "nas01-env";
  paths = with pkgs; [
    borgbackup        # Borg backup server (SSH-based, no daemon needed)
    samba             # SMB/CIFS file sharing
    nfs-utils         # NFS userspace tools (rpcbind, showmount, etc.)
    rsync             # Data migration (btrfs → ZFS)
    smartmontools     # Drive health monitoring (smartctl)
    hdparm            # Drive identification and management
    lsof              # Open file/socket inspection
    ncdu              # Disk usage analyzer
    htop              # System monitoring
    home-manager      # Manages starship, shell aliases, bash config (run: home-manager switch --flake .#scott)
    tailscale         # VPN (tailscaled daemon + tailscale CLI)
  ];
}
