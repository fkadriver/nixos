# Bitwarden Secrets Management

This module enables dynamic secrets management using Bitwarden. Only your Bitwarden API credentials are stored encrypted in sops - all other secrets are fetched from Bitwarden at build/boot time.

## Benefits

- **Single Source of Truth**: All secrets stored in Bitwarden vault
- **Easy Updates**: Update secrets in Bitwarden, rebuild to apply
- **Minimal Encryption**: Only API credentials need sops encryption
- **No Expiration**: API keys don't expire like session tokens
- **Automatic Refresh**: Secrets sync every 6 hours via systemd timer

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Bitwarden Vault (Cloud)                                     │
│ ├── SSH Keys (as Secure Notes)                              │
│ ├── Service Secrets (Tailscale, etc.)                       │
│ └── Other credentials                                       │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ API Key Authentication
                          │
┌─────────────────────────┴───────────────────────────────────┐
│ NixOS System                                                 │
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ sops-encrypted secrets/secrets.yaml                    │  │
│ │ ├── bitwarden.client_id                                │  │
│ │ └── bitwarden.client_secret                            │  │
│ └────────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          ▼                                   │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Build Time: Activation Script                          │  │
│ │ └── Fetches SSH keys → ~/.ssh/                         │  │
│ └────────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          ▼                                   │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Boot Time: systemd Service (+ 6h timer)                │  │
│ │ └── Fetches secrets → /run/bitwarden-secrets/          │  │
│ └────────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          ▼                                   │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ Services (Tailscale, etc.)                             │  │
│ │ └── Read from /run/bitwarden-secrets/                  │  │
│ └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Create Bitwarden API Key

1. Log in to [Bitwarden web vault](https://vault.bitwarden.com)
2. Go to **Settings** → **Security** → **Keys**
3. Under **API Key**, click **View API Key**
4. Enter master password and copy both:
   - `client_id`: `user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
   - `client_secret`: `xxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### 2. Test API Key

```bash
# Set credentials
export BW_CLIENTID="user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export BW_CLIENTSECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Login and unlock
bw login --apikey
export BW_SESSION=$(bw unlock --raw)

# Verify
bw status
```

### 3. Store Credentials in sops

```bash
cd ~/git/nixos

# Edit secrets (creates if doesn't exist)
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

Add:

```yaml
# Bitwarden credentials for fetching secrets dynamically
bitwarden:
  client_id: user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  client_secret: xxxxxxxxxxxxxxxxxxxxxxxxxxxx
  master_password: your-bitwarden-master-password
```

**Important:** All three values are required:
- `client_id` and `client_secret` from API Key settings
- `master_password` to unlock the vault automatically

Save and exit (`:wq`).

### 4. Organize Secrets in Bitwarden

#### SSH Keys

You can store SSH keys in two ways:

**Option 1: SSH Key Item Type (Recommended)**
- **Item Type**: SSH Key
- **Name**: Descriptive like "GitHub SSH Key"
- Paste your private key when prompted
- Bitwarden will automatically parse and store it

**Option 2: Secure Note**
- **Item Type**: Secure Note
- **Name**: Descriptive like "SSH Key - GitHub"
- **Notes**: Paste entire private key:
  ```
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
  ...
  -----END OPENSSH PRIVATE KEY-----
  ```

The module supports both formats automatically.

#### Service Secrets (Tailscale, etc.)

Create a **Login** or **Secure Note**:
- **Name**: "Tailscale Auth Key"
- **Password** field: `tskey-auth-xxxxxxxxxxxxxxxxxxxxx`

### 5. Get Item IDs

```bash
# List all items with IDs
bw list items | jq -r '.[] | "\(.id) - \(.name)"'

# Search for specific items
bw list items | jq -r '.[] | select(.name | contains("SSH")) | "\(.id) - \(.name)"'
```

Example output:
```
a1b2c3d4-5678-90ab-cdef-1234567890ab - SSH Key - GitHub
b2c3d4e5-6789-01bc-def1-234567890abc - Tailscale Auth Key
```

You can use either:
- **UUID**: `"a1b2c3d4-5678-90ab-cdef-1234567890ab"` (stable, recommended)
- **Name**: `"SSH Key - GitHub"` (readable, but breaks if renamed)

### 6. Configure NixOS

See the example configuration below for a complete setup.

### 7. Rebuild

```bash
sudo nixos-rebuild switch --flake .#yourhostname
```

## Example Configuration

Here's a complete example showing SSH keys and Tailscale integration:

```nix
{ config, lib, pkgs, ... }: {
  # Import the bitwarden module
  imports = [
    ./modules/bitwarden.nix
  ];

  # Enable Bitwarden secrets management
  services.bitwarden = {
    enable = true;

    # SSH keys to fetch from Bitwarden
    # These are fetched at build time and written to ~/.ssh/
    sshKeys = {
      # Primary SSH key (e.g., for GitHub)
      github = {
        user = "scott";                    # Linux username
        keyName = "id_ed25519";            # Filename in ~/.ssh/
        itemId = "SSH Key - GitHub";       # Bitwarden item name or UUID
      };

      # Legacy SSH key (for old servers)
      legacy = {
        user = "scott";
        keyName = "id_ed25519_legacy";
        itemId = "SSH Key - Legacy Servers";
      };
    };

    # Other secrets (non-SSH)
    # These are fetched at boot and written to /run/bitwarden-secrets/
    secrets = {
      tailscale_auth_key = {
        name = "tailscale_auth_key";       # Filename in /run/bitwarden-secrets/
        itemId = "Tailscale Auth Key";     # Bitwarden item name or UUID
        field = "password";                # Field to extract (password/notes/username)
        mode = "0400";                     # File permissions
      };

      # Example: Database password
      # postgres_password = {
      #   name = "postgres_password";
      #   itemId = "PostgreSQL Database";
      #   field = "password";
      #   mode = "0400";
      # };
    };
  };

  # Tailscale configuration using the fetched auth key
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = lib.mkIf config.services.bitwarden.enable
      "/run/bitwarden-secrets/tailscale_auth_key";
  };
}
```

## Configuration Reference

### SSH Keys (`sshKeys`)

Each SSH key configuration requires:

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `user` | string | Linux username who owns the key | `"scott"` |
| `keyName` | string | Filename in `~/.ssh/` | `"id_ed25519"` |
| `itemId` | string | Bitwarden item UUID or name | `"SSH Key - GitHub"` |

**Behavior:**
- Fetched during activation (when you run `nixos-rebuild switch`)
- Written to `/home/{user}/.ssh/{keyName}`
- Permissions: `0600` (read/write by owner only)
- Owner: `{user}:{user}`

### Secrets (`secrets`)

Each secret configuration requires:

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `name` | string | Filename in `/run/bitwarden-secrets/` | `"tailscale_auth_key"` |
| `itemId` | string | Bitwarden item UUID or name | `"Tailscale Auth Key"` |
| `field` | string | Field to extract: `password`, `notes`, `username` | `"password"` |
| `mode` | string | File permissions (octal) | `"0400"` |

**Behavior:**
- Fetched at boot by systemd service
- Written to `/run/bitwarden-secrets/{name}`
- Refreshed every 6 hours by systemd timer
- Stored in tmpfs (memory only, cleared on reboot)
- Permissions: As specified in `mode`

## How It Works

### Build/Activation Time (SSH Keys)

1. During `nixos-rebuild switch`, activation script runs
2. Decrypts API credentials from sops
3. Authenticates to Bitwarden with API key
4. Fetches each configured SSH key from vault
5. Writes keys to `~/.ssh/` with correct permissions

### Boot Time (Service Secrets)

1. Systemd service `bitwarden-secrets-sync.service` starts after network
2. Decrypts API credentials from sops
3. Authenticates to Bitwarden with API key
4. Fetches each configured secret from vault
5. Writes secrets to `/run/bitwarden-secrets/`
6. Timer runs every 6 hours to refresh secrets

## Updating Secrets

### SSH Keys

```bash
# Update key in Bitwarden, then rebuild
sudo nixos-rebuild switch --flake .#hostname
```

### Service Secrets

```bash
# Option 1: Restart sync service
sudo systemctl restart bitwarden-secrets-sync.service

# Option 2: Just rebuild
sudo nixos-rebuild switch --flake .#hostname
```

## Troubleshooting

### Check Service Status

```bash
# Service status
sudo systemctl status bitwarden-secrets-sync.service

# Live logs
sudo journalctl -u bitwarden-secrets-sync.service -f

# Recent logs
sudo journalctl -u bitwarden-secrets-sync.service -n 50
```

### Verify Secrets

```bash
# Runtime secrets (services)
ls -la /run/bitwarden-secrets/

# SSH keys
ls -la ~/.ssh/
```

### Manual Bitwarden Test

```bash
# Get credentials from sops
export BW_CLIENTID=$(sudo cat /run/secrets/bitwarden/client_id)
export BW_CLIENTSECRET=$(sudo cat /run/secrets/bitwarden/client_secret)
export BW_PASSWORD=$(sudo cat /run/secrets/bitwarden/master_password)

# Login with API key
bw login --apikey

# Unlock vault (using master password from environment)
export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)

# Test fetching an item
bw get item "SSH Key - GitHub"
bw get item "Tailscale Auth Key"

# Extract specific field
bw get item "Tailscale Auth Key" | jq -r '.login.password'
```

### Force Secrets Refresh

```bash
# Restart sync service
sudo systemctl restart bitwarden-secrets-sync.service

# Check if it worked
sudo systemctl status bitwarden-secrets-sync.service
ls -la /run/bitwarden-secrets/
```

### Common Issues

**Issue**: `bw: command not found`
- **Solution**: The module automatically installs `bitwarden-cli`, but if running manual commands, install it: `nix-shell -p bitwarden-cli`

**Issue**: API authentication fails
- **Solution**: Check that API credentials in `secrets/secrets.yaml` match your Bitwarden account. Re-copy from web vault if needed.

**Issue**: Item not found
- **Solution**: Verify item name/UUID is correct. Use `bw list items | jq` to confirm exact names.

**Issue**: Secrets not updating
- **Solution**: Check timer status: `sudo systemctl status bitwarden-secrets-sync.timer`. Manually restart service if needed.

## Security Notes

### Credentials in sops
- API credentials (client_id, client_secret) and master password stored encrypted with sops-nix (Age encryption)
- Only readable by root at runtime
- API keys don't expire (unlike session tokens)
- Can be revoked from Bitwarden web vault if compromised
- Master password used only to unlock vault during automated fetches

### Runtime Secrets
- Stored in `/run/bitwarden-secrets/` (tmpfs, memory only)
- Automatically cleared on reboot
- File permissions set per secret configuration
- Only accessible to root or services with explicit permissions

### SSH Keys
- Written to disk at `~/.ssh/`
- Permissions: `0600` (read/write by owner only)
- Owned by specified user
- Persisted across reboots

### Network Requirement
- Secrets sync requires network access to Bitwarden servers
- Service waits for `network-online.target` before starting
- If network unavailable at boot, secrets won't be fetched
- SSH keys are written at build time, so they persist without network

## Field Types Reference

When configuring `secrets`, the `field` parameter specifies which part of the Bitwarden item to extract:

| Field Type | Use Case | Example Item Type |
|------------|----------|-------------------|
| `password` | Auth keys, API tokens, passwords | Login items |
| `notes` | Multi-line secrets, SSH keys, certificates | Secure Notes |
| `username` | Usernames, client IDs | Login items |

The Bitwarden CLI returns items as JSON. For example:

```json
{
  "login": {
    "username": "admin",
    "password": "secret123"
  },
  "notes": "This is a note"
}
```

- `field = "password"` extracts `.login.password`
- `field = "notes"` extracts `.notes`
- `field = "username"` extracts `.login.username`

## Advanced: Custom Field Extraction

If you need to extract custom fields or nested JSON, you can modify the module or use a wrapper script. The module currently supports the three standard fields above.
