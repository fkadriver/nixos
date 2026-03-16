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

# Source nix profile if available (sudo shells don't inherit it)
# shellcheck disable=SC1091
[[ -f /etc/profile.d/nix.sh ]] && source /etc/profile.d/nix.sh

# Install Nix if not present (check by binary path, not just PATH)
NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
if ! command -v nix &>/dev/null && [[ ! -x "${NIX_BIN}" ]]; then
    # Remove stale Nix installer backup files that block re-installation
    for f in /etc/bash.bashrc /etc/bashrc /etc/zshrc /etc/profile.d/nix.sh; do
        [[ -f "${f}.backup-before-nix" ]] && rm -f "${f}.backup-before-nix"
    done

    echo "Installing Nix..."
    sh <(curl -L https://nixos.org/nix/install) --daemon --yes
    # Source nix after fresh install
    # shellcheck disable=SC1091
    source /etc/profile.d/nix.sh
else
    echo "Nix already installed, skipping."
    # Ensure nix is in PATH if source didn't pick it up
    export PATH="${NIX_BIN%/nix}:${PATH}"
fi

# Enable experimental features (nix-command and flakes) if not already set
NIX_CONF="/etc/nix/nix.conf"
if ! grep -q "experimental-features" "${NIX_CONF}" 2>/dev/null; then
    echo "Enabling nix-command and flakes in ${NIX_CONF}..."
    echo "experimental-features = nix-command flakes" >> "${NIX_CONF}"
    systemctl restart nix-daemon
    sleep 2
fi

# Install/update packages to the nas01 Nix profile
echo "Updating Nix packages..."
nix --extra-experimental-features 'nix-command flakes' \
    profile install --profile "${NIX_PROFILE}" "${REPO_DIR}#nas01-env"

# Apply home-manager config as scott (must run as user, not root)
echo "Applying home-manager config (starship, shell aliases)..."
sudo -u scott "${NIX_PROFILE}/bin/home-manager" switch --flake "${REPO_DIR}#scott"

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
