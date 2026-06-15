{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
  config = {
    environment.systemPackages = [
      # icsactivate: save current latitude generation, then switch to latitude-ics.
      # icsleave: restore the saved generation (run from either host).
      # Both scripts must be present on both latitude and latitude-ics so that
      # icsleave is available after icsactivate switches the running system.
      (pkgs.writeShellScriptBin "icsactivate" ''
        set -euo pipefail
        STATE=/var/lib/ics-env/prev-generation
        VMRUN=${pkgs.vmware-workstation}/bin/vmrun
        VM_DIR=$HOME/vms

        if [ "$(hostname)" = "latitude-ics" ]; then
          echo "Already in ICS environment (hostname is latitude-ics)."
          exit 0
        fi

        current=$(sudo nix-env --list-generations \
          --profile /nix/var/nix/profiles/system \
          | awk '/\(current\)/{print $1}')

        sudo mkdir -p /var/lib/ics-env
        echo "$current" | sudo tee "$STATE" > /dev/null

        echo "Saved generation $current → $STATE"
        echo "Switching to latitude-ics configuration…"
        cd ~/git/nixos
        sudo nixos-rebuild switch --flake ~/git/nixos#latitude-ics

        echo "Enabling shared folders on all VMs…"
        while IFS= read -r -d "" vmx; do
          echo "  $vmx"
          "$VMRUN" enableSharedFolders "$vmx" 2>/dev/null \
            && echo "    shared folders enabled" \
            || echo "    (skipped — VM may need to be powered on first)"
        done < <(find "$VM_DIR" -maxdepth 2 -name "*.vmx" -print0)
      '')

      (pkgs.writeShellScriptBin "icsleave" ''
        set -euo pipefail
        STATE=/var/lib/ics-env/prev-generation

        if [ ! -f "$STATE" ]; then
          echo "No saved generation found; rolling back to the previous generation."
          sudo nixos-rebuild switch --rollback
          exit 0
        fi

        target=$(cat "$STATE")
        echo "Rolling back to generation $target…"
        sudo nix-env --switch-generation "$target" \
          --profile /nix/var/nix/profiles/system
        sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
        sudo rm -f "$STATE"
        echo "Returned to generation $target (latitude)."
      '')
    ];
  };
}
