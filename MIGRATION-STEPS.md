# Bitwarden Module Migration Steps

You've already completed the consolidation. Now follow these steps to migrate to the new system:

## Step 1: Get Your Bitwarden Item Names

Your BW_SESSION has expired. Re-authenticate:

```bash
export BW_CLIENTID="<your_client_id>"
export BW_CLIENTSECRET="<your_client_secret>"
bw login --apikey  # If not already logged in
export BW_SESSION=$(bw unlock --raw)
```

Then list your SSH keys:

```bash
bw list items | jq -r '.[] | "\(.id) - \(.name)"' | grep -i ssh
```

Make note of the exact item names (or UUIDs) for:
- Your GitHub SSH key
- Your legacy SSH key
- Any other secrets (Tailscale, etc.)

## Step 2: Update secrets/secrets.yaml

Edit your encrypted secrets file:

```bash
cd ~/git/nixos
sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

**Replace the entire contents** with:

```yaml
# Bitwarden credentials for fetching secrets dynamically
bitwarden:
  client_id: user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  client_secret: xxxxxxxxxxxxxxxxxxxxxxxxxxxx
  master_password: your-bitwarden-master-password
```

Replace with:
- Your actual API credentials from Bitwarden Settings → Security → Keys
- Your Bitwarden master password (used to unlock vault automatically)

**IMPORTANT:**
- All three values are required for automated unlocking
- Remove all the old secrets (ssh keys, tailscale auth, etc.) - they will now be fetched from Bitwarden dynamically!

## Step 3: Update Item Names in Config Files

Edit these files and replace the placeholder item names with your actual Bitwarden item names:

1. **modules/laptop-kde.nix** (lines 26 and 31):
   - Change `"SSH Key - GitHub"` to match your actual Bitwarden item name
   - Change `"SSH Key - Legacy Servers"` to match your actual item name

2. **modules/laptop-xfce.nix** (lines 26 and 31):
   - Same changes as above

Example:
```nix
services.bitwarden = {
  enable = true;
  sshKeys = {
    github = {
      user = "scott";
      keyName = "id_ed25519";
      itemId = "GitHub SSH Key";  # ← Your actual item name from step 1
    };
    legacy = {
      user = "scott";
      keyName = "id_ed25519_legacy";
      itemId = "Old Servers SSH";  # ← Your actual item name from step 1
    };
  };
};
```

## Step 4: Test the Configuration

```bash
# Check if the config is valid
sudo nixos-rebuild dry-build --flake .#latitude  # or your hostname

# If no errors, do a test rebuild
sudo nixos-rebuild test --flake .#latitude

# Check if SSH keys were installed
ls -la ~/.ssh/
```

## Step 5: Apply Permanently

```bash
sudo nixos-rebuild switch --flake .#latitude
```

## Step 6: Verify Everything Works

```bash
# Check if secrets sync service is running
sudo systemctl status bitwarden-secrets-sync.service

# View logs
sudo journalctl -u bitwarden-secrets-sync.service -n 50

# Verify SSH keys exist
ls -la ~/.ssh/id_ed25519*
```

## Troubleshooting

### If SSH keys aren't being fetched:

1. Make sure your SSH keys in Bitwarden are stored as **Secure Notes** with the private key in the **Notes** field
2. Check activation script logs: `sudo journalctl -b | grep -i bitwarden`

### If secrets sync fails:

1. Check that credentials (API + master password) are correct in secrets.yaml
2. Make sure you can manually authenticate:
   ```bash
   export BW_CLIENTID=$(sudo cat /run/secrets/bitwarden/client_id)
   export BW_CLIENTSECRET=$(sudo cat /run/secrets/bitwarden/client_secret)
   export BW_PASSWORD=$(sudo cat /run/secrets/bitwarden/master_password)
   bw login --apikey
   export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
   bw list items
   ```

### If itemId not found:

1. Double-check the exact spelling of your Bitwarden item names
2. Consider using UUIDs instead (more stable): `itemId = "a1b2c3d4-5678-90ab-cdef-1234567890ab";`

## What Changed?

**Old system:**
- All secrets stored encrypted in secrets.yaml
- Used `bitwarden-secrets` with `secretName = "ssh/github_key"`

**New system:**
- Only API credentials in secrets.yaml
- Uses `bitwarden` with `itemId = "SSH Key - GitHub"`
- Fetches secrets from Bitwarden vault dynamically
- Auto-refreshes every 6 hours

## Need Help?

See [docs/bitwarden.md](docs/bitwarden.md) for full documentation.
