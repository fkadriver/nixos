# Bitwarden Secrets Management Setup Guide

This guide explains how to use Bitwarden with sops-nix to manage secrets in your NixOS configuration.

## Overview

The setup uses:
- **Bitwarden**: Store your secrets (SSH keys, API keys, passwords)
- **sops-nix**: Encrypt secrets in your git repository
- **age**: Encryption tool used by sops

## Initial Setup

### 1. Generate Age Key

On your first NixOS build with bitwarden-secrets enabled, an age key will be automatically generated at `/var/lib/sops-nix/key.txt`.

To manually generate or view your public key:

```bash
# Generate key (only if not exists)
sudo age-keygen -o /var/lib/sops-nix/key.txt

# Get public key
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

**Save this public key** - you'll need it to encrypt secrets.

### 2. Create Secrets Directory

```bash
cd /path/to/nixos
mkdir -p secrets
```

### 3. Create .sops.yaml Configuration

Create `.sops.yaml` in your repository root:

```yaml
keys:
  - &admin_scott age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # Replace with your public key

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *admin_scott
```

### 4. Create Secrets Template

```bash
cat > secrets/secrets.yaml <<'EOF'
# Tailscale authentication key
# Get from: https://login.tailscale.com/admin/settings/keys
tailscale:
  auth_key: tskey-auth-xxxxx-xxxxxx

# SSH private keys
# Store your SSH private keys here
ssh:
  github_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_GITHUB_SSH_PRIVATE_KEY
    -----END OPENSSH PRIVATE KEY-----

  server_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    YOUR_SERVER_SSH_PRIVATE_KEY
    -----END OPENSSH PRIVATE KEY-----

# Syncthing device ID
syncthing:
  device_id: XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX

# WiFi passwords
wifi:
  home_network: your_wifi_password_here
EOF
```

### 5. Extract Secrets from Bitwarden

Login to Bitwarden CLI:

```bash
# First time login
export BW_SESSION=$(bw login --raw)

# If already logged in, just unlock
export BW_SESSION=$(bw unlock --raw)
```

Extract secrets:

```bash
# Get an SSH key from Bitwarden
bw get item "GitHub SSH Key" | jq -r '.notes'

# Get a password
bw get password "WiFi Home Network"

# Get Tailscale auth key
bw get notes "Tailscale Auth Key"
```

**Or use the helper script:**

```bash
sudo /etc/bitwarden-extract-secrets.sh secrets/secrets.yaml
```

### 6. Encrypt Secrets with sops

```bash
# Encrypt the secrets file
sops -e secrets/secrets.yaml > secrets/secrets.yaml.enc

# Move encrypted version to final location
mv secrets/secrets.yaml.enc secrets/secrets.yaml

# Edit encrypted secrets later
sops secrets/secrets.yaml
```

### 7. Add secrets/ to .gitignore

```bash
echo "secrets/secrets.yaml.tmp" >> .gitignore
echo ".sops.yaml" >> .gitignore  # Optional: keep this local
```

**Important:** The encrypted `secrets/secrets.yaml` should be committed to git. The `.tmp` files should NOT.

## Enable in Configuration

### Example: SSH Keys

In your host configuration (e.g., `hosts/latitude.nix`):

```nix
{
  imports = [
    ./latitude-hardware.nix
    inputs.self.nixosModules.common
    inputs.self.nixosModules.laptop
    inputs.self.nixosModules.user-scott
  ];

  # Enable Bitwarden secrets management
  services.bitwarden-secrets = {
    enable = true;
    secretsFile = ../secrets/secrets.yaml;

    # SSH keys to install
    sshKeys = {
      id_ed25519 = {
        user = "scott";
        secretName = "ssh/github_key";
      };
      server_key = {
        user = "scott";
        secretName = "ssh/server_key";
      };
    };
  };

  config = {
    networking.hostName = "latitude-nixos";
    system.stateVersion = "25.04";
  };
}
```

SSH keys will be automatically installed to `/home/scott/.ssh/id_ed25519` and `/home/scott/.ssh/server_key`.

### Example: Tailscale Auth Key

Update `modules/tailscale.nix` to use the secret:

```nix
{ config, ... }: {
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale/auth_key".path;
  };

  # ... rest of configuration
}
```

### Example: WiFi Password

Update `modules/laptop.nix`:

```nix
{ config, ... }: {
  networking.networkmanager.ensureProfiles = {
    profiles = {
      JEN_ACRES = {
        connection = {
          id = "JEN_ACRES";
          type = "wifi";
          autoconnect = "true";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "JEN_ACRES";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk-file = config.sops.secrets."wifi/home_network".path;
        };
      };
    };
  };
}
```

## Bitwarden Organization

Recommended structure in Bitwarden:

```
📁 NixOS
  📄 SSH Key - GitHub (notes: private key content)
  📄 SSH Key - Servers (notes: private key content)
  📄 Tailscale Auth Key (notes: tskey-auth-xxxxx)
  📄 WiFi - Home (password field)
  📄 Syncthing Device ID (notes: device ID)
```

## Updating Secrets

### Update from Bitwarden

```bash
# 1. Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# 2. Edit encrypted secrets
sops secrets/secrets.yaml

# 3. Update values from Bitwarden
bw get item "GitHub SSH Key" | jq -r '.notes'
# Copy and paste into sops editor

# 4. Save (sops automatically re-encrypts)

# 5. Rebuild system
sudo nixos-rebuild switch --flake .#latitude
```

### Add New Machine

When setting up a new machine:

```bash
# 1. On the new machine, get the age public key
sudo age-keygen -y /var/lib/sops-nix/key.txt

# 2. On your development machine, add the key to .sops.yaml
keys:
  - &admin_scott age1xxxxx  # Original key
  - &new_machine age1yyyyy  # New machine key

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *admin_scott
          - *new_machine

# 3. Re-encrypt secrets for all keys
sops updatekeys secrets/secrets.yaml

# 4. Commit and push
git add .sops.yaml secrets/secrets.yaml
git commit -m "Add new machine to secrets"
git push
```

## Security Best Practices

1. **Never commit unencrypted secrets** to git
2. **Keep `/var/lib/sops-nix/key.txt` secure** - this is the decryption key
3. **Backup your age keys** securely (e.g., in Bitwarden)
4. **Use different auth keys** for each Tailscale machine
5. **Rotate secrets regularly**, especially API keys
6. **Review `.gitignore`** to ensure temporary files aren't committed

## Troubleshooting

### "Failed to decrypt" error

```bash
# Verify you have the correct age key
sudo cat /var/lib/sops-nix/key.txt

# Verify the public key matches .sops.yaml
sudo age-keygen -y /var/lib/sops-nix/key.txt

# Re-encrypt if needed
sops updatekeys secrets/secrets.yaml
```

### SSH key not appearing

```bash
# Check secret was decrypted
sudo ls -la /run/secrets/

# Check file permissions
ls -la /home/scott/.ssh/

# Check sops configuration
sudo journalctl -u sops-nix
```

### Bitwarden CLI not logged in

```bash
# Check status
bw status

# Login
export BW_SESSION=$(bw login --raw your_email@example.com)

# Or unlock if already logged in
export BW_SESSION=$(bw unlock --raw)

# Verify
bw status | jq
```

## Advanced: Automated Secret Extraction

Create a script to automatically extract and update secrets from Bitwarden:

```bash
#!/usr/bin/env bash
# sync-secrets-from-bitwarden.sh

export BW_SESSION=$(bw unlock --raw)

# Create temporary unencrypted file
cat > secrets/secrets.yaml.tmp <<EOF
tailscale:
  auth_key: $(bw get notes "Tailscale Auth Key")

ssh:
  github_key: |
$(bw get item "GitHub SSH Key" | jq -r '.notes' | sed 's/^/    /')

  server_key: |
$(bw get item "Server SSH Key" | jq -r '.notes' | sed 's/^/    /')

wifi:
  home_network: $(bw get password "WiFi Home")
EOF

# Encrypt with sops
sops -e secrets/secrets.yaml.tmp > secrets/secrets.yaml

# Clean up
rm secrets/secrets.yaml.tmp

echo "Secrets updated from Bitwarden and encrypted"
```

Make it executable:
```bash
chmod +x sync-secrets-from-bitwarden.sh
```

## Reference

- [sops-nix GitHub](https://github.com/Mic92/sops-nix)
- [age encryption](https://github.com/FiloSottile/age)
- [Bitwarden CLI](https://bitwarden.com/help/cli/)
