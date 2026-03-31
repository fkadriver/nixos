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
# Use nix build + nix-env --set to reliably update the profile on every run
echo "Updating Nix packages..."
NAS01_ENV=$(nix --extra-experimental-features 'nix-command flakes' \
    build --no-link --print-out-paths "${REPO_DIR}#nas01-env")
nix-env --profile "${NIX_PROFILE}" --set "${NAS01_ENV}"

# Add nas01 Nix profile to system-wide PATH
echo "Configuring PATH..."
cat > /etc/profile.d/nas01-nix.sh << 'EOF'
# Add nas01 Nix profile to PATH (managed by hosts/nas01/apply.sh)
export PATH="/nix/var/nix/profiles/nas01/bin:$PATH"
EOF

# Increase inotify limits (required by Syncthing, Docker, and systemd services)
# max_user_watches: number of files that can be watched (default: 8192)
# max_user_instances: number of inotify descriptors per user (default: 128 — systemd exhausts this)
printf 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=8192\n' > /etc/sysctl.d/99-inotify.conf
sysctl --system

# Add scott to borg group (needed to access borg repos)
if getent group borg &>/dev/null; then
    usermod -aG borg scott
fi

# Apply home-manager config as scott (must run as user, not root)
echo "Applying home-manager config (starship, shell aliases)..."
sudo -u scott env PATH="${PATH}" "${NIX_PROFILE}/bin/home-manager" switch -b backup --flake "${REPO_DIR}#scott"

# Deploy SSH keys from secrets.yaml via sops
# Requires: age key at /var/lib/sops-nix/key.txt (generate once with: sudo age-keygen -y /var/lib/sops-nix/key.txt)
SSH_DIR="/home/scott/.ssh"
AGE_KEY="/var/lib/sops-nix/key.txt"
SECRETS="${REPO_DIR}/secrets/secrets.yaml"

if [[ -f "${AGE_KEY}" ]]; then
    echo "Deploying SSH keys from secrets.yaml..."
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"

    deploy_key() {
        local secret_path="$1"
        local dest="$2"
        local mode="$3"
        # Convert "ssh/key_name" → ["ssh"]["key_name"] for sops --extract
        local extract_path
        extract_path=$(echo "${secret_path}" | awk -F/ '{for(i=1;i<=NF;i++) printf "[\"" $i "\"]"}')
        local tmp
        tmp=$(mktemp)
        if SOPS_AGE_KEY_FILE="${AGE_KEY}" "${NIX_PROFILE}/bin/sops" \
                --decrypt --extract "${extract_path}" "${SECRETS}" > "${tmp}"; then
            install -m "${mode}" -o scott -g scott "${tmp}" "${dest}"
        else
            rm -f "${tmp}"
            echo "WARNING: Failed to deploy ${dest}"
        fi
    }

    deploy_key "ssh/id_ed25519"               "${SSH_DIR}/id_ed25519"               600
    deploy_key "ssh/id_ed25519.pub"            "${SSH_DIR}/id_ed25519.pub"            644
    deploy_key "ssh/id_ed25519_github"         "${SSH_DIR}/id_ed25519_github"         600
    deploy_key "ssh/id_ed25519_github.pub"     "${SSH_DIR}/id_ed25519_github.pub"     644
    deploy_key "ssh/id_ed25519_legacy"         "${SSH_DIR}/id_ed25519_legacy"         600
    deploy_key "ssh/id_ed25519_legacy.pub"     "${SSH_DIR}/id_ed25519_legacy.pub"     644
    deploy_key "ssh/opnsense_admin_ed25519"    "${SSH_DIR}/opnsense_admin_ed25519"    600
    deploy_key "ssh/opnsense_admin_ed25519.pub" "${SSH_DIR}/opnsense_admin_ed25519.pub" 644

    echo "SSH keys deployed to ${SSH_DIR}"
else
    echo "WARNING: Age key not found at ${AGE_KEY} — skipping SSH key deployment."
    echo "  To generate: sudo age-keygen -o ${AGE_KEY}"
    echo "  Then add the public key to .sops.yaml and re-encrypt: sops updatekeys secrets/secrets.yaml"
fi

# Allow hddtemp and smartctl without password (needed for drive temps in btop and temps alias)
echo "Configuring sudoers for drive temperature tools..."
cat > /etc/sudoers.d/drive-temps << 'EOF'
# Allow drive temperature tools without password prompt
scott ALL=(ALL) NOPASSWD: /nix/var/nix/profiles/nas01/bin/hddtemp
scott ALL=(ALL) NOPASSWD: /nix/var/nix/profiles/nas01/bin/smartctl
EOF
chmod 440 /etc/sudoers.d/drive-temps

# rsyslog forwarding to log01
echo "Installing rsyslog forwarding config..."
if ! dpkg -l rsyslog &>/dev/null; then
    echo "  rsyslog not found — installing..."
    apt-get install -y rsyslog
fi
install -m 644 "${NAS01_DIR}/config/rsyslog-log01.conf" /etc/rsyslog.d/50-log01-forward.conf
systemctl enable --now rsyslog
systemctl restart rsyslog

# Samba config
echo "Installing Samba config..."
mkdir -p /etc/samba /var/log/samba /run/samba
install -m 644 "${NAS01_DIR}/config/smb.conf" /etc/samba/smb.conf
# Create samba db dir
mkdir -p /var/lib/samba/private

# NFS exports
echo "Installing NFS exports..."
install -m 644 "${NAS01_DIR}/config/exports" /etc/exports

# hd-idle spindown config
echo "Installing hd-idle config..."
install -m 644 "${NAS01_DIR}/config/hd-idle" /etc/default/hd-idle

# Systemd service files (Nix-installed smbd/nmbd/tailscaled)
echo "Installing systemd services..."
install -m 644 "${NAS01_DIR}/config/systemd/smbd.service" /etc/systemd/system/smbd.service
install -m 644 "${NAS01_DIR}/config/systemd/nmbd.service" /etc/systemd/system/nmbd.service
install -m 644 "${NAS01_DIR}/config/systemd/tailscaled.service" /etc/systemd/system/tailscaled.service
install -m 644 "${NAS01_DIR}/config/systemd/syncthing.service" /etc/systemd/system/syncthing.service
systemctl daemon-reload

echo ""
echo "=== apt prerequisites (run if not already installed) ==="
echo "  # Kernel integration (must match Ubuntu kernel via DKMS — cannot use Nix equivalents):"
echo "  sudo apt install nfs-kernel-server zfsutils-linux"
echo ""
echo "  # Drive spindown (hd-idle daemon — manages spindown timers for HDDs):"
echo "  sudo apt install hd-idle"
echo "  # Config deployed above to /etc/default/hd-idle"
echo "  # Note: sdX assignments can shift on reboot — verify with: lsblk -o NAME,SIZE,MODEL,SERIAL"
echo ""
echo "  # Docker Engine (systemd service + docker group — use apt, not the Nix package):"
echo "  sudo apt install docker.io"
echo "  sudo usermod -aG docker scott"
echo ""
echo "  # Bootstrap dependencies (needed before Nix is installed):"
echo "  sudo apt install curl git"
echo "  # Note: tar is pre-installed on Ubuntu"
echo ""
echo "=== Enable services ==="
echo "  sudo systemctl enable --now hd-idle"
echo "  sudo systemctl enable --now smbd nmbd"
echo "  sudo systemctl enable --now nfs-kernel-server"
echo "  sudo exportfs -ra"
echo "  sudo systemctl enable --now tailscaled"
echo "  sudo tailscale up   # authenticate to Tailscale network (one-time)"
echo "  sudo systemctl enable --now syncthing"
echo "  # Then configure Syncthing (run as scott, after service starts):"
echo "  bash ${NAS01_DIR}/config/syncthing-setup.sh"
echo ""
echo "=== iDrive e360 (cloud backup) ==="
echo "  iDrive e360 cannot be packaged via Nix (no stable download URL; installer"
echo "  modifies system paths at install time). Download the .deb directly from:"
echo "    https://www.idrive.com/endpoint-backup/  ->  Add Devices  ->  Linux tab"
echo "  See archive/modules/idrive-e360.nix and archive/pkgs/idrive-e360/ for a"
echo "  prior NixOS packaging attempt that was archived due to these limitations."
echo ""
echo "=== One-time setup ==="
echo "  sudo bash ${NAS01_DIR}/config/borg-server-setup.sh"
echo "  sudo bash ${NAS01_DIR}/config/zfs-setup.sh   # after connecting drives"
echo ""
echo "Done."
