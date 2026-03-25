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

# Login with API key
bw login --apikey

# Unlock vault (will prompt for master password)
export BW_SESSION=$(bw unlock --raw)

# Verify
bw status
```

**Important:** The API key authenticates you to Bitwarden's servers, but you still need your **master password** to unlock and decrypt your vault locally. This is by design - Bitwarden uses zero-knowledge encryption, so the master password never leaves your device.

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

## Adding New Machines

When adding a new machine to your NixOS configuration, you need to give it access to the encrypted secrets.

### 1. Get the New Machine's AGE Public Key

On the new machine (after first build):

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

This outputs something like: `age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### 2. Add the Key to `.sops.yaml`

Edit `.sops.yaml` in your repository root:

```yaml
keys:
  - &admin age1xxxxxxxxxxxxxx        # Your existing key
  - &newmachine age1yyyyyyyyyyyyyy   # New machine's key

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *admin
          - *newmachine
```

### 3. Re-encrypt Secrets with All Keys

This is the critical step - re-encrypt the secrets file so all keys can decrypt it:

```bash
# On NixOS, specify the key file location
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops updatekeys secrets/secrets.yaml
```

This command:
- Uses `SOPS_AGE_KEY_FILE` to tell sops where to find the private key
- Decrypts the file using your current key
- Re-encrypts it for all keys listed in `.sops.yaml`
- The file remains encrypted, but now all listed machines can decrypt it

**Note**: The NixOS private key is at `/var/lib/sops-nix/key.txt`, not in the default locations sops checks, so you must specify `SOPS_AGE_KEY_FILE`.

### 4. Commit and Deploy

```bash
git add .sops.yaml secrets/secrets.yaml
git commit -m "Add AGE key for newmachine"
git push

# On the new machine, rebuild to use the secrets
sudo nixos-rebuild switch --flake .#newmachine
```

**Important**: Always run `sops updatekeys` after modifying `.sops.yaml` - the secrets file won't work on the new machine until it's re-encrypted with the new key!

## Updating Secrets

### SSH Keys

To replace an SSH key stored as a **SSH Key type item** (type 5) in Bitwarden:

```bash
# 1. Unlock vault
export BW_SESSION=$(bw unlock --raw)
bw sync

# 2. Generate a new key (or skip if reusing an existing one)
ssh-keygen -t ed25519 -C "scott@hostname" -f /tmp/new_ssh_key

# 3. Inspect the item to confirm its structure
bw get item <item-id> | jq '{type, notes, sshKey}'

# 4. Update the item (SSH Key type — has sshKey.privateKey)
NEW_PRIV=$(cat /tmp/new_ssh_key)
NEW_PUB=$(cat /tmp/new_ssh_key.pub)
FINGERPRINT=$(ssh-keygen -lf /tmp/new_ssh_key.pub | awk '{print $2}')

bw get item <item-id> \
  | jq --arg priv "$NEW_PRIV" --arg pub "$NEW_PUB" --arg fp "$FINGERPRINT" \
      '.sshKey.privateKey = $priv | .sshKey.publicKey = $pub | .sshKey.keyFingerprint = $fp' \
  | bw encode \
  | bw edit item <item-id>

# 4. (Alternative) Update the item (Secure Note type — key stored in notes)
NEW_PRIV=$(cat /tmp/new_ssh_key)
bw get item <item-id> \
  | jq --arg key "$NEW_PRIV" '.notes = $key' \
  | bw encode \
  | bw edit item <item-id>

# 5. Clean up temp files
rm -f /tmp/new_ssh_key /tmp/new_ssh_key.pub

# 6. Redeploy — activation script re-fetches keys from Bitwarden
sudo nixos-rebuild switch --flake .#hostname
```

**Known SSH Key Item IDs** (from `modules/bitwarden-scott.nix`):

| Key Name | BW Item ID | BW Item Name |
|----------|-----------|--------------|
| `id_ed25519_github` | `4eb21873-7ca7-4114-9b0e-b3c90164bc7e` | github ssh |
| `id_ed25519_legacy` | `40b6efe1-5699-46a1-875f-b39800fd3105` | scott (ssh-ed25519) |
| `opnsense_admin_ed25519` | `21397fb4-104e-4528-90ef-b3ce00fe7c43` | opnsense ssh |

After updating `id_ed25519_github`, also register the new public key at
**github.com → Settings → SSH and GPG keys → New SSH key**.

### Service Secrets

```bash
# Option 1: Restart sync service
sudo systemctl restart bitwarden-secrets-sync.service

# Option 2: Just rebuild
sudo nixos-rebuild switch --flake .#hostname
```

### Re-encrypt After Adding/Removing Keys

Whenever you modify `.sops.yaml` (add or remove AGE keys):

```bash
# Re-encrypt all secrets with the updated key list
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops updatekeys secrets/secrets.yaml

# If you have multiple secrets files
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops updatekeys secrets/secrets.yaml
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops updatekeys secrets/other-secrets.yaml
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
