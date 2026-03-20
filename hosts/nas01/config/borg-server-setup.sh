#!/usr/bin/env bash
# Borg backup server setup for nas01
# Run once after initial deployment.
#
# Clients connect as 'scott' via SSH using Bitwarden-managed keys.
# No separate borg user or forced command needed — trusted home network behind Tailscale.
# /pool/borg is a symlink to the Backups directory on the 18TB WD drive.
#
# See docs/borg-backup.md for full setup and client initialization steps.

set -euo pipefail

BORG_REPOS_DIR="/pool/borg/repos"

echo "=== Borg Server Setup ==="

# Create repo directories for each client
echo "Creating repo directories..."
mkdir -p \
    "${BORG_REPOS_DIR}/latitude" \
    "${BORG_REPOS_DIR}/vm01" \
    "${BORG_REPOS_DIR}/airbook-darwin"
chown -R scott:scott "${BORG_REPOS_DIR}"
chmod 750 "${BORG_REPOS_DIR}"
echo "Repo dirs created under ${BORG_REPOS_DIR}"

echo ""
echo "=== Authorize client SSH keys ==="
echo "Clients connect as scott using Bitwarden-managed keys (deployed by apply.sh)."
echo "Run the following to authorize the key:"
echo ""
echo "  grep -qF \"\$(cat ~/.ssh/id_ed25519_legacy.pub)\" ~/.ssh/authorized_keys \\"
echo "    || cat ~/.ssh/id_ed25519_legacy.pub >> ~/.ssh/authorized_keys"
echo ""
echo "Key usage:"
echo "  id_ed25519_legacy — all clients (latitude, vm01, airbook-darwin, borg-* shell aliases)"
echo ""
echo "Next: initialize each client repo — see docs/borg-backup.md Step 4."
