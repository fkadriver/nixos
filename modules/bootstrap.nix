{ inputs, ... }@flakeContext:
# Stage-1 "bootstrap" system for a staged install (see docs/installing.md).
#
# The installer ISO installs `<host>-bootstrap` (generated per host in
# flake.nix): the host's own hardware.nix plus this module. Everything here
# is small and in the public binary cache, so the install never builds
# anything big inside the ISO's RAM disk (the airbook's first install died
# compiling orca-slicer there). It deliberately includes the pieces the full
# build needs as a *build environment*:
#   - Tailscale, joined interactively by `bootstrap-join`, so the nas01
#     cache proxy (:8383) and peers are reachable
#   - sops-nix + Bitwarden, so once scripts/enroll-host.sh has added this
#     host's age key, a rebuild delivers id_ed25519_legacy, which peer
#     substitution needs
#   - distributed-builds, so the final build fetches fleet-built paths from
#     peers and offloads big builds to latitude/vm01
# The host's full config replaces all of this in enroll-host.sh's last step.
{ config, lib, pkgs, ... }:
let
  host = config.networking.hostName;
  pubKeyFile = "/var/lib/sops-nix/key.pub";

  bootstrapJoin = pkgs.writeShellScriptBin "bootstrap-join" ''
    set -euo pipefail
    echo "=== Joining the tailnet as ${host} (tag:device) ==="
    echo "Open the login URL below on another device and approve it."
    # sudo tailscale is NOPASSWD for scott (user-scott.nix).
    sudo tailscale up --ssh --accept-routes --advertise-tags=tag:device --hostname=${host}
    echo
    echo "Joined. This host's sops age public key:"
    cat ${pubKeyFile}
    echo
    echo "Next, on latitude:  ~/git/nixos/scripts/enroll-host.sh ${config.networking.hostName}"
  '';
in
{
  imports = [
    inputs.self.nixosModules.common
    inputs.self.nixosModules.user-scott
    inputs.self.nixosModules.wireless
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.bitwarden-scott
    inputs.self.nixosModules.distributed-builds
  ];

  config = {
    system.nixos.label = "bootstrap";

    # Standard disko layout (modules/disko-config.nix), forced here so the
    # bootstrap boots even on hosts whose hardware.nix still mounts the old
    # install by UUID. enroll-host.sh refuses to switch such a host to its
    # full config until that hardware.nix is fixed too.
    fileSystems."/" = lib.mkForce {
      device = "/dev/mapper/main_vg-root";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    fileSystems."/boot" = lib.mkForce {
      device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
    swapDevices = lib.mkForce [ { device = "/dev/mapper/main_vg-swap"; } ];
    boot.initrd.kernelModules = [ "dm-snapshot" ];
    # The disko layout is always EFI; some hosts (vm01) set the loader in
    # default.nix rather than hardware.nix.
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

    # sops-nix generates the age key at activation (its generate-age-key
    # step runs even while decryption still fails, before enrollment).
    # Publish the public half world-readable so enroll-host.sh can read it
    # without sudo.
    sops.age.generateKey = true;
    system.activationScripts.bootstrapAgePubkey = lib.stringAfter [ "generate-age-key" ] ''
      if [ -f ${config.sops.age.keyFile} ]; then
        ${pkgs.age}/bin/age-keygen -y ${config.sops.age.keyFile} > ${pubKeyFile}.tmp
        chmod 644 ${pubKeyFile}.tmp
        mv ${pubKeyFile}.tmp ${pubKeyFile}
      fi
    '';

    # Same as the fleet: sshd on loopback, key auth. It also creates the
    # /etc/ssh host key that Tailscale SSH presents and the full config
    # keeps, so enroll-host.sh can pin it in distributed-builds.nix.
    services.openssh = {
      enable = true;
      listenAddresses = [ { addr = "127.0.0.1"; port = 22; } ];
      settings.PasswordAuthentication = false;
    };

    environment.systemPackages = [ bootstrapJoin pkgs.age pkgs.git ];

    services.getty.helpLine = ''

      ==========================================
      ${host}: bootstrap stage (not the full config yet)
      ==========================================
      1. Log in as scott and run:   bootstrap-join
         (joins Tailscale; open the URL it prints)
      2. Then on latitude run:      ~/git/nixos/scripts/enroll-host.sh ${host}
         (adds this host's age key, then builds the full config)
    '';
  };
}
