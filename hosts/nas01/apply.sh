#!/usr/bin/env bash
# Deploy nas01 Nix packages and config from this repo.
# Run from the repo root on nas01 (or via ssh):
#   cd ~/git/nixos && sudo ./hosts/nas01/apply.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAS01_DIR="${REPO_DIR}/hosts/nas01"
NIX_PROFILE="/nix/var/nix/profiles/nas01"

echo "=== nas01 Deploy ==="
echo "Repo: ${REPO_DIR}"

# Install Nix if not present
if ! command -v nix &>/dev/null; then
    echo "Installing Nix..."
    sh <(curl -L https://nixos.org/nix/install) --daemon
    # Source nix after install
    # shellcheck disable=SC1091
    source /etc/profile.d/nix.sh
fi

# Install/update packages to the nas01 Nix profile
echo "Updating Nix packages..."
nix profile install --profile "${NIX_PROFILE}" "${REPO_DIR}#nas01-env"

# Samba config
echo "Installing Samba config..."
mkdir -p /etc/samba /var/log/samba /run/samba
install -m 644 "${NAS01_DIR}/config/smb.conf" /etc/samba/smb.conf
# Create samba db dir
mkdir -p /var/lib/samba/private

# NFS exports
echo "Installing NFS exports..."
install -m 644 "${NAS01_DIR}/config/exports" /etc/exports

# Systemd service files (Nix-installed smbd/nmbd)
echo "Installing systemd services..."
install -m 644 "${NAS01_DIR}/config/systemd/smbd.service" /etc/systemd/system/smbd.service
install -m 644 "${NAS01_DIR}/config/systemd/nmbd.service" /etc/systemd/system/nmbd.service
systemctl daemon-reload

echo ""
echo "=== apt prerequisites (run if not already installed) ==="
echo "  sudo apt install nfs-kernel-server zfsutils-linux"
echo ""
echo "=== Enable services ==="
echo "  sudo systemctl enable --now smbd nmbd"
echo "  sudo systemctl enable --now nfs-kernel-server"
echo "  sudo exportfs -ra"
echo ""
echo "=== One-time setup ==="
echo "  sudo bash ${NAS01_DIR}/config/borg-server-setup.sh"
echo "  sudo bash ${NAS01_DIR}/config/zfs-setup.sh   # after connecting drives"
echo ""
echo "Done."
