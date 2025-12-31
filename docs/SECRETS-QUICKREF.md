# Bitwarden Secrets - Quick Reference

## One-Time Setup

```bash
# 1. Get your age public key (after first nixos-rebuild)
sudo age-keygen -y /var/lib/sops-nix/key.txt
# Output: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 2. Create .sops.yaml in repo root
cat > .sops.yaml <<EOF
keys:
  - &admin age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *admin
EOF

# 3. Create secrets directory
mkdir -p secrets
```

## Daily Workflow

### Extract Secret from Bitwarden

```bash
# Login
export BW_SESSION=$(bw unlock --raw)

# Get SSH key
bw get item "GitHub SSH Key" | jq -r '.notes'

# Get password
bw get password "WiFi Password"

# Get note
bw get notes "Tailscale Auth Key"
```

### Create/Edit Secrets

```bash
# Edit encrypted secrets (will create if doesn't exist)
sops secrets/secrets.yaml

# Or edit plaintext then encrypt
vim secrets/secrets.yaml
sops -e -i secrets/secrets.yaml
```

### Apply to System

```bash
# Test configuration
sudo nixos-rebuild test --flake .#latitude

# Apply permanently
sudo nixos-rebuild switch --flake .#latitude
```

## Common Tasks

### Add SSH Key

```nix
# In your host config
services.bitwarden-secrets = {
  enable = true;
  sshKeys = {
    id_ed25519 = {
      user = "scott";
      secretName = "ssh/github_key";
    };
  };
};
```

```yaml
# In secrets/secrets.yaml
ssh:
  github_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    ...
    -----END OPENSSH PRIVATE KEY-----
```

### Use Tailscale Auth Key

```nix
# Define secret
sops.secrets."tailscale/auth_key" = {
  restartUnits = [ "tailscaled.service" ];
};

# Reference in service
services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth_key".path;
```

### WiFi Password

```nix
sops.secrets."wifi/home".mode = "0400";

networking.networkmanager.ensureProfiles.profiles.HOME = {
  wifi-security.psk-file = config.sops.secrets."wifi/home".path;
};
```

## Adding New Machine

```bash
# 1. On new machine, get public key
NEW_KEY=$(sudo age-keygen -y /var/lib/sops-nix/key.txt)

# 2. Add to .sops.yaml
keys:
  - &admin age1xxxxx
  - &newmachine age1yyyyy  # $NEW_KEY

# 3. Re-encrypt for all keys
sops updatekeys secrets/secrets.yaml

# 4. Commit and deploy
git add .sops.yaml secrets/secrets.yaml
git commit -m "Add new machine to secrets"
git push
```

## Troubleshooting

```bash
# Check secret was decrypted
sudo ls -la /run/secrets/

# View sops logs
sudo journalctl -u sops-nix

# Test decryption manually
sudo sops -d secrets/secrets.yaml

# Verify age key
sudo cat /var/lib/sops-nix/key.txt

# Check public key
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

## Quick Commands

```bash
# Bitwarden
bw login                          # First time
export BW_SESSION=$(bw unlock --raw)
bw list items                     # List all
bw get item "Name"                # Get specific item
bw sync                           # Sync vault

# sops
sops secrets/secrets.yaml         # Edit encrypted
sops -d secrets/secrets.yaml      # Decrypt to stdout
sops -e -i secrets/secrets.yaml   # Encrypt in place
sops updatekeys secrets/secrets.yaml  # Re-encrypt for new keys

# age
age-keygen -o key.txt             # Generate key
age-keygen -y key.txt             # Show public key
age -r PUBLIC_KEY -e file         # Encrypt file
age -d -i key.txt file.age        # Decrypt file
```

## Secret Paths Reference

| Secret Type | Path in secrets.yaml | Deployed To |
|------------|---------------------|-------------|
| SSH Key | `ssh/github_key` | `/home/user/.ssh/id_ed25519` |
| Tailscale | `tailscale/auth_key` | `/run/secrets/tailscale_auth_key` |
| WiFi | `wifi/home` | `/run/secrets/wifi_home` |
| Custom | `myservice/api_key` | `/run/secrets/myservice_api_key` |

## Security Checklist

- [ ] `.gitignore` includes `secrets/*.tmp` and `secrets/*.dec`
- [ ] Never commit unencrypted `secrets.yaml`
- [ ] Backup `/var/lib/sops-nix/key.txt` securely
- [ ] Use different auth keys per machine
- [ ] Rotate secrets regularly
- [ ] Review committed files before push
- [ ] Store age keys in Bitwarden as backup

## Example secrets.yaml Structure

```yaml
tailscale:
  auth_key: tskey-auth-xxxxx-xxxxxx

ssh:
  github_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----

  server_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----

wifi:
  home: SuperSecretPassword123

syncthing:
  device_id: XXXXXXX-XXXXXXX-XXXXXXX

services:
  api_key: sk_live_xxxxxxxxxxxxxx

database:
  postgres_password: db_password_here
```

## Links

- Full Guide: [bitwarden-secrets-setup.md](bitwarden-secrets-setup.md)
- Examples: [bitwarden-examples.nix](bitwarden-examples.nix)
- sops-nix: https://github.com/Mic92/sops-nix
- Bitwarden CLI: https://bitwarden.com/help/cli/
