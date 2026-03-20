#!/usr/bin/env bash
# Borg backup server setup for nas01
# Run once after initial deployment to configure the borg user and SSH access.
#
# Borg server requires NO daemon - it uses SSH with a restricted command.
# Each client authenticates with its own SSH key, restricted to its repo path.
#
# /pool/borg is a symlink to the Backups directory on the 18TB WD drive.

set -euo pipefail

BORG_USER="borg"
BORG_HOME="/pool/borg"
BORG_REPOS_DIR="${BORG_HOME}/repos"

echo "=== Borg Server Setup ==="

# Create borg system user if it doesn't exist
if ! id "${BORG_USER}" &>/dev/null; then
    useradd \
        --system \
        --shell /bin/bash \
        --home-dir "${BORG_HOME}" \
        --create-home \
        "${BORG_USER}"
    echo "Created user: ${BORG_USER}"
fi

# Create repos directory
mkdir -p "${BORG_REPOS_DIR}"
chown -R "${BORG_USER}:${BORG_USER}" "${BORG_HOME}"
chmod 700 "${BORG_HOME}"

# Set up SSH authorized_keys
SSH_DIR="${BORG_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"
chown -R "${BORG_USER}:${BORG_USER}" "${SSH_DIR}"

echo ""
echo "=== Add client SSH keys ==="
echo "For each client, add an entry to:"
echo "  ${AUTH_KEYS}"
echo ""
echo "Format for each client (one line per client):"
cat <<'EOF'
command="borg serve --restrict-to-path /pool/borg/repos/<hostname>",restrict ssh-ed25519 AAAA... user@hostname
EOF
echo ""
echo "The 'restrict' keyword disables port forwarding, X11 forwarding, etc."
echo "The 'command=' forces borg serve regardless of what the client requests."
echo ""
echo "Repo dirs to create (one per client):"
echo "  mkdir -p /pool/borg/repos/latitude"
echo "  mkdir -p /pool/borg/repos/vm01"
echo "  mkdir -p /pool/borg/repos/prodesk"
echo "  mkdir -p /pool/borg/repos/airbook-darwin"
echo "  chown -R borg:borg /pool/borg/repos/"
echo ""
echo "=== Current NixOS client borg SSH keys (from this repo) ==="
echo "Check modules/borg-backup.nix and secrets/secrets.yaml for the public keys"
echo ""
echo "Setup complete. NAS is ready to accept borg SSH connections on port 22."
