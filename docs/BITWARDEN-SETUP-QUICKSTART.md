# Bitwarden Dynamic Secrets - Quick Start Guide

This is a step-by-step guide to migrate your NixOS configuration to use dynamic Bitwarden secrets.

## Overview

**What changes:**
- Before: All secrets encrypted in `secrets/secrets.yaml` with sops
- After: Only BW_SESSION in sops, all other secrets fetched from Bitwarden on-demand

**Benefits:**
- Update secrets in Bitwarden, rebuild to apply
- No manual sops editing for secret updates
- Single source of truth for all secrets

## Step 1: Prepare Bitwarden

### 1.1 Log in and Get Session Key

```bash
# Unlock Bitwarden and get session key
export BW_SESSION=$(bw unlock --raw)

# Verify it works
bw status
# Should show: "status":"unlocked"
```

### 1.2 Organize Your Secrets

Create items in Bitwarden for each secret:

#### SSH Keys (Secure Notes)

1. Create a new **Secure Note** in Bitwarden
2. Name: `SSH Key - GitHub`
3. In the Notes field, paste your private key:
   ```bash
   cat ~/.ssh/id_ed25519
   ```
4. Repeat for `SSH Key - Legacy Servers` with your `id_ed25519_legacy` key

#### Tailscale Auth Key

1. Get your auth key from https://login.tailscale.com/admin/settings/keys
2. Create new auth key:
   - Enable: Reusable
   - Expiration: 90 days or Never
   - Description: "NixOS Latitude"
3. Create a **Login** item in Bitwarden:
   - Name: `Tailscale Auth Key`
   - Password: `tskey-auth-xxxxxxxxxxxxxxxxxxxxx` (paste the key)

### 1.3 Get Item IDs

```bash
# List all items to find IDs
bw list items | jq -r '.[] | "\(.id) - \(.name)"'

# Or filter for specific items
bw list items | jq -r '.[] | select(.name | contains("SSH")) | "\(.id) - \(.name)"'
```

Example output:
```
a1b2c3d4-1234-5678-abcd-ef1234567890 - SSH Key - GitHub
b2c3d4e5-5678-9012-bcde-f12345678901 - SSH Key - Legacy Servers
c3d4e5f6-9012-3456-cdef-123456789012 - Tailscale Auth Key
```

**Note**: You can use either the UUID or the exact item name (recommended to use name for simplicity).

## Step 2: Update secrets.yaml

Currently your `secrets/secrets.yaml` has all secrets. We'll replace it with just the BW_SESSION.

### 2.1 Backup Current Secrets

```bash
cd ~/git/nixos
cp secrets/secrets.yaml secrets/secrets.yaml.backup
```

### 2.2 Update secrets.yaml

```bash
# Edit the secrets file
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

Replace ALL content with:

```yaml
# Bitwarden session key for dynamic secret fetching
bitwarden:
  session: PASTE_YOUR_BW_SESSION_HERE
```

To get your session key:
```bash
echo $BW_SESSION
```

Copy that value and paste it in the file above.

Save and exit (`:wq` in vim).

## Step 3: Update Host Configuration

Edit your host config (e.g., `hosts/latitude/default.nix`):

```nix
{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
    ];
    config = {
      networking = {
        hostName = "latitude";
      };

      # ====== ADD THIS SECTION ======
      # Enable dynamic Bitwarden secrets
      services.bitwarden-dynamic = {
        enable = true;

        # SSH keys
        sshKeys = {
          github = {
            user = "scott";
            keyName = "id_ed25519";
            itemId = "SSH Key - GitHub";
          };
          legacy = {
            user = "scott";
            keyName = "id_ed25519_legacy";
            itemId = "SSH Key - Legacy Servers";
          };
        };

        # Other secrets
        secrets = {
          tailscale_auth_key = {
            name = "tailscale_auth_key";
            itemId = "Tailscale Auth Key";
            field = "password";
            mode = "0400";
          };
        };
      };
      # ====== END NEW SECTION ======

      # Borg backup to nas01
      services.borg-backup = {
        enable = true;
        repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/latitude";
        encryption.passphraseFile = "/etc/borg-passphrase";
        sshKeyFile = "/home/scott/.ssh/id_ed25519";
      };

      system = {
        stateVersion = "25.04";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
```

## Step 4: Test and Rebuild

### 4.1 First, Verify Bitwarden Access

```bash
# Make sure you can access Bitwarden
export BW_SESSION=$(bw unlock --raw)
bw get item "SSH Key - GitHub"
# Should show the item details
```

### 4.2 Rebuild NixOS

```bash
cd ~/git/nixos
sudo nixos-rebuild switch --flake .#latitude
```

### 4.3 Verify Secrets Were Fetched

```bash
# Check systemd service
sudo systemctl status bitwarden-secrets-sync.service

# Check logs
sudo journalctl -u bitwarden-secrets-sync.service -n 50

# Verify runtime secrets
ls -la /run/bitwarden-secrets/
# Should show: tailscale_auth_key

# Verify SSH keys
ls -la ~/.ssh/
# Should show: id_ed25519, id_ed25519_legacy

# Test SSH keys
ssh-add -l
# Or try connecting to a server
```

## Step 5: Repeat for Other Hosts

Apply the same configuration to `airbook` and any other hosts:

```bash
# Copy the bitwarden-dynamic configuration to airbook
cd ~/git/nixos/hosts/airbook/
# Edit default.nix and add the same bitwarden-dynamic section
```

## Troubleshooting

### BW_SESSION Not Found

```bash
# Check if secret exists
sudo ls -la /run/secrets/bitwarden/session
sudo cat /run/secrets/bitwarden/session

# If not found, verify sops configuration
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
```

### Secrets Not Syncing

```bash
# Check service status
sudo systemctl status bitwarden-secrets-sync.service

# View full logs
sudo journalctl -u bitwarden-secrets-sync.service -e

# Try manual sync
sudo systemctl restart bitwarden-secrets-sync.service
```

### SSH Keys Not Installing

```bash
# Check activation script output
sudo nixos-rebuild switch --flake .#latitude --show-trace

# Manually test Bitwarden access
export BW_SESSION=$(sudo cat /run/secrets/bitwarden/session)
bw get item "SSH Key - GitHub" | jq -r '.notes'
```

### Network Issues

The system needs internet access to fetch secrets from Bitwarden. If offline:

1. Secrets won't sync at boot (service will fail)
2. SSH keys won't be updated during rebuild
3. Old cached data may be used for runtime secrets

To fix: Connect to network and run:
```bash
sudo systemctl restart bitwarden-secrets-sync.service
```

## How Often Are Secrets Updated?

- **SSH keys**: Updated every time you run `nixos-rebuild switch`
- **Runtime secrets**: Updated at boot + every 6 hours via systemd timer
- **Manual refresh**: `sudo systemctl restart bitwarden-secrets-sync.service`

## Updating a Secret

When you need to update a secret:

1. Update it in Bitwarden (web vault or CLI)
2. For SSH keys: `sudo nixos-rebuild switch --flake .#latitude`
3. For runtime secrets: `sudo systemctl restart bitwarden-secrets-sync.service`

That's it! No need to edit sops files.

## Security Notes

- BW_SESSION is stored encrypted with sops-nix (only readable by root)
- Runtime secrets in `/run/bitwarden-secrets/` are in tmpfs (memory only, cleared on reboot)
- SSH keys written to `~/.ssh/` with mode 0600
- Bitwarden session keys typically expire after 1 hour of inactivity

## What to Do If BW_SESSION Expires

If you get authentication errors:

1. Unlock Bitwarden: `export BW_SESSION=$(bw unlock --raw)`
2. Update the session in sops: `SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml`
3. Paste the new BW_SESSION value
4. Rebuild: `sudo nixos-rebuild switch --flake .#latitude`

**Tip**: Use a Bitwarden API key (not a session) if you want a longer-lived credential. Session keys are meant for interactive use and expire.

## Next Steps

- See [bitwarden-dynamic-secrets.md](./bitwarden-dynamic-secrets.md) for full documentation
- See [examples/bitwarden-dynamic-example.nix](../examples/bitwarden-dynamic-example.nix) for more examples
- Consider storing borg-passphrase in Bitwarden too!
