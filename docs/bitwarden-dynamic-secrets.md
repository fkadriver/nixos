# Dynamic Bitwarden Secrets

This system allows you to store only your Bitwarden session key in sops-encrypted storage, and dynamically fetch all other secrets from Bitwarden at build/boot time.

## Architecture

1. **Encrypted Storage (sops)**: Only stores the Bitwarden session key (`BW_SESSION`)
2. **Build/Boot Time**: NixOS activation scripts and systemd services query Bitwarden using the session key
3. **Runtime Secrets**: Secrets are written to `/run/bitwarden-secrets/` for services or `~/.ssh/` for SSH keys

## Benefits

- **Single Source of Truth**: All secrets stored in Bitwarden
- **Easy Updates**: Update secrets in Bitwarden, rebuild NixOS to apply
- **No Manual Sync**: No need to manually extract and re-encrypt secrets
- **Minimal sops Usage**: Only the session key needs encryption

## Setup

### 1. Get Your Bitwarden Session Key

First, log in to Bitwarden and get your session key:

```bash
# If not logged in yet
export BW_SESSION=$(bw login --raw)

# If already logged in but locked
export BW_SESSION=$(bw unlock --raw)

# Verify it works
bw status
```

The session key will look like: `xxxxxxxxxxxxxxxxxxxxxxxxxxx==`

### 2. Store Session Key in sops

Create/update your `secrets/secrets.yaml` with ONLY the Bitwarden session key:

```bash
cd ~/git/nixos

# Edit secrets (will decrypt if already exists, or create new)
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

Add this content:

```yaml
# Bitwarden session key for fetching secrets dynamically
bitwarden:
  session: xxxxxxxxxxxxxxxxxxxxxxxxxxx==
```

Save and exit (`:wq` in vim).

### 3. Organize Your Secrets in Bitwarden

For each secret, create a Bitwarden item:

#### SSH Keys

- **Item Type**: Secure Note
- **Name**: Something descriptive like "SSH Key - GitHub" or "SSH Key - Legacy Servers"
- **Notes Field**: Paste the entire private key content:
  ```
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
  ...
  -----END OPENSSH PRIVATE KEY-----
  ```

#### Tailscale Auth Key

- **Item Type**: Login or Secure Note
- **Name**: "Tailscale Auth Key"
- **Password Field**: Paste your auth key (starts with `tskey-auth-`)

### 4. Get Bitwarden Item IDs

You need the unique ID or exact name for each item:

```bash
# List all items
bw list items | jq -r '.[] | "\(.id) - \(.name)"'

# Or search for specific items
bw list items | jq -r '.[] | select(.name | contains("SSH")) | "\(.id) - \(.name)"'
```

Example output:
```
a1b2c3d4-5678-90ab-cdef-1234567890ab - SSH Key - GitHub
b2c3d4e5-6789-01bc-def1-234567890abc - SSH Key - Legacy Servers
c3d4e5f6-7890-12cd-ef12-34567890abcd - Tailscale Auth Key
```

You can use either the UUID or the exact name (in quotes).

### 5. Configure Your Hosts

In your host configuration (e.g., `hosts/latitude/default.nix`), replace the old `bitwarden` module with `bitwarden-dynamic`:

```nix
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    # ... other imports ...
  ];

  # Enable dynamic Bitwarden secrets
  services.bitwarden-dynamic = {
    enable = true;

    # SSH keys to fetch from Bitwarden
    sshKeys = {
      github = {
        user = "scott";
        keyName = "id_ed25519";
        itemId = "SSH Key - GitHub";  # Or use UUID
      };
      legacy = {
        user = "scott";
        keyName = "id_ed25519_legacy";
        itemId = "SSH Key - Legacy Servers";  # Or use UUID
      };
    };

    # Other secrets (non-SSH)
    secrets = {
      tailscale_auth_key = {
        name = "tailscale_auth_key";
        itemId = "Tailscale Auth Key";
        field = "password";  # Use "password" field for login items
        mode = "0400";
      };
    };
  };

  # Tailscale will use the dynamically fetched key
  # (see modules/tailscale.nix for how it references /run/bitwarden-secrets/tailscale_auth_key)
}
```

### 6. Update Tailscale Module

The Tailscale module needs to reference the dynamically fetched secret. Edit `modules/tailscale.nix`:

```nix
services.tailscale = {
  enable = true;
  useRoutingFeatures = "both";
  extraUpFlags = [
    "--accept-routes"
    "--ssh"
  ];
  # Use dynamically fetched auth key
  authKeyFile = lib.mkIf
    (config.services ? bitwarden-dynamic && config.services.bitwarden-dynamic.enable)
    "/run/bitwarden-secrets/tailscale_auth_key";
};
```

### 7. Rebuild and Test

```bash
# Rebuild NixOS
sudo nixos-rebuild switch --flake .#latitude

# Check if secrets were fetched
sudo systemctl status bitwarden-secrets-sync.service

# Verify secrets exist
ls -la /run/bitwarden-secrets/
ls -la ~/.ssh/
```

## How It Works

### At Build/Activation Time

1. **Activation Script** (`bitwarden-ssh-keys`):
   - Runs during `nixos-rebuild switch`
   - Decrypts BW_SESSION from sops
   - Queries Bitwarden for each configured SSH key
   - Writes keys to `~/.ssh/` with correct permissions

### At Boot Time

1. **Systemd Service** (`bitwarden-secrets-sync.service`):
   - Starts after network is online
   - Decrypts BW_SESSION from sops
   - Queries Bitwarden for each configured secret
   - Writes secrets to `/run/bitwarden-secrets/`
   - Services like Tailscale can reference these files

2. **Systemd Timer** (`bitwarden-secrets-sync.timer`):
   - Runs every 6 hours to refresh secrets
   - Ensures secrets stay up-to-date

## Updating Secrets

When you update a secret in Bitwarden:

### For SSH Keys
```bash
# Just rebuild - activation script will fetch latest
sudo nixos-rebuild switch --flake .#latitude
```

### For Service Secrets (Tailscale, etc.)
```bash
# Restart the sync service to fetch latest
sudo systemctl restart bitwarden-secrets-sync.service

# Or just rebuild
sudo nixos-rebuild switch --flake .#latitude
```

## Troubleshooting

### Check Service Status
```bash
sudo systemctl status bitwarden-secrets-sync.service
sudo journalctl -u bitwarden-secrets-sync.service -f
```

### Manually Test Bitwarden Access
```bash
# Get session key from sops
sudo cat /run/secrets/bitwarden/session
export BW_SESSION="<paste-session-key>"

# Test fetching an item
bw get item "SSH Key - GitHub"
```

### Verify Secrets Location
```bash
# Runtime secrets
ls -la /run/bitwarden-secrets/

# SSH keys
ls -la ~/.ssh/
```

### Re-sync Secrets
```bash
# Force a sync
sudo systemctl restart bitwarden-secrets-sync.service

# Check logs
sudo journalctl -u bitwarden-secrets-sync.service -n 50
```

## Security Notes

1. **BW_SESSION Key**:
   - Stored encrypted with sops-nix
   - Only readable by root at runtime
   - Session keys typically expire after 1 hour of inactivity

2. **Runtime Secrets**:
   - Stored in `/run/bitwarden-secrets/` (tmpfs, memory only)
   - Automatically removed on reboot
   - File permissions set per secret configuration

3. **SSH Keys**:
   - Written to disk at `~/.ssh/`
   - Mode 0600 (read/write by owner only)
   - Owned by the specified user

4. **Network Requirement**:
   - Secrets sync requires network access to Bitwarden servers
   - On boot, service waits for `network-online.target`
   - If network is unavailable, old cached secrets may be used

## Migration from Old bitwarden.nix

1. Keep both modules during transition
2. Update one secret at a time
3. Test thoroughly before removing old module
4. Remove old secrets from `secrets/secrets.yaml` after migration complete

## Item ID vs Item Name

You can use either:
- **UUID**: `"a1b2c3d4-5678-90ab-cdef-1234567890ab"` (more stable)
- **Name**: `"SSH Key - GitHub"` (more readable, but breaks if renamed)

Best practice: Use names for personal vaults, UUIDs for shared vaults.
