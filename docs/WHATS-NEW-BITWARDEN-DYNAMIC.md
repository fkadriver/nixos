# What's New: Dynamic Bitwarden Secrets

## Summary

This update introduces a new **dynamic Bitwarden secrets management system** that eliminates the need to manually update sops-encrypted secrets when your passwords or SSH keys change.

## What Changed

### Before (Old System - `bitwarden.nix`)
- All secrets stored encrypted in `secrets/secrets.yaml`
- To update a secret:
  1. Update it in Bitwarden
  2. Manually extract it with `bw` CLI
  3. Edit `secrets/secrets.yaml` with sops
  4. Re-encrypt with age
  5. Rebuild NixOS
- Error-prone and tedious

### After (New System - `bitwarden-dynamic.nix`)
- Only BW_SESSION key stored in `secrets/secrets.yaml`
- All other secrets fetched from Bitwarden at build/boot time
- To update a secret:
  1. Update it in Bitwarden
  2. Rebuild NixOS (or restart service)
- Single source of truth: Bitwarden

## New Files

1. **`modules/bitwarden-dynamic.nix`**
   - New NixOS module for dynamic secret fetching
   - Provides `services.bitwarden-dynamic` option
   - Includes systemd service + timer for runtime secrets
   - Includes activation script for SSH keys

2. **`docs/BITWARDEN-SETUP-QUICKSTART.md`**
   - Step-by-step setup guide
   - Complete migration instructions
   - Troubleshooting tips

3. **`docs/bitwarden-dynamic-secrets.md`**
   - Full technical documentation
   - Architecture explanation
   - API reference

4. **`examples/bitwarden-dynamic-example.nix`**
   - Complete example host configuration
   - Shows all configuration options

## Modified Files

1. **`modules/tailscale.nix`**
   - Updated to support both old and new secret systems
   - Checks for `bitwarden-dynamic` first, falls back to `bitwarden-secrets`
   - Backwards compatible

## How It Works

### Architecture

```
┌─────────────────┐
│   Bitwarden     │  (Single source of truth)
│   Web Vault     │
└────────┬────────┘
         │
         │ BW_SESSION key
         │ (only this is in sops)
         ▼
┌─────────────────┐
│ secrets.yaml    │  (Encrypted with sops-nix)
│ bitwarden:      │
│   session: xxx  │
└────────┬────────┘
         │
         │ Decrypted at build/boot
         ▼
┌─────────────────────────────────────┐
│  bitwarden-secrets-sync.service     │
│  (systemd service)                  │
│  - Queries Bitwarden with session   │
│  - Writes to /run/bitwarden-secrets/│
└─────────────────────────────────────┘
         │
         ├─────────────────────┬─────────────────────┐
         ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐
│ ~/.ssh/id_ed25519│  │ /run/bitwarden-  │  │  Services    │
│ (SSH keys)       │  │ secrets/         │  │ (Tailscale,  │
│                  │  │ tailscale_auth   │  │  etc.)       │
└──────────────────┘  └──────────────────┘  └──────────────┘
```

### Timing

- **SSH Keys**: Fetched during `nixos-rebuild switch` (activation script)
- **Runtime Secrets**: Fetched at boot + every 6 hours (systemd timer)
- **Manual Refresh**: `sudo systemctl restart bitwarden-secrets-sync.service`

## Migration Path

You can migrate incrementally:

1. Both `bitwarden.nix` and `bitwarden-dynamic.nix` can coexist
2. The Tailscale module checks for `bitwarden-dynamic` first
3. Start with one host (e.g., latitude)
4. Once stable, migrate other hosts
5. Eventually remove old `bitwarden.nix` module

## Configuration Example

```nix
# In your host config (hosts/latitude/default.nix)
services.bitwarden-dynamic = {
  enable = true;

  # SSH keys to install
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

  # Other secrets (for services)
  secrets = {
    tailscale_auth_key = {
      name = "tailscale_auth_key";
      itemId = "Tailscale Auth Key";
      field = "password";
      mode = "0400";
    };
  };
};
```

## Benefits

1. **Single Source of Truth**: All secrets in Bitwarden
2. **Easy Updates**: No more manual sops editing
3. **Less Error-Prone**: No copy-paste mistakes
4. **Automatic Rotation**: Update in Bitwarden, rebuild to apply
5. **Better Security**: Fewer places secrets are stored
6. **Audit Trail**: Bitwarden tracks secret changes

## Getting Started

See [BITWARDEN-SETUP-QUICKSTART.md](./BITWARDEN-SETUP-QUICKSTART.md) for step-by-step instructions.

## Backwards Compatibility

The new system is **fully backwards compatible**:

- Old `bitwarden-secrets` module still works
- Tailscale module supports both systems
- You can run both modules side-by-side during migration
- No breaking changes to existing configs

## Future Enhancements

Potential future additions:

1. **More Secrets**: Add borg-passphrase, WiFi passwords, etc.
2. **API Keys**: Use Bitwarden API keys instead of session keys for longer expiry
3. **Secrets Rotation**: Automatic rotation of certain secrets
4. **Multiple Vaults**: Support for organization vaults
5. **Backup Secrets**: Fallback to cached secrets if Bitwarden unavailable

## Questions?

- **Setup Help**: See [BITWARDEN-SETUP-QUICKSTART.md](./BITWARDEN-SETUP-QUICKSTART.md)
- **Technical Docs**: See [bitwarden-dynamic-secrets.md](./bitwarden-dynamic-secrets.md)
- **Examples**: See [../examples/bitwarden-dynamic-example.nix](../examples/bitwarden-dynamic-example.nix)
