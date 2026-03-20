# Borg Backup Configuration

Borg Backup is a deduplicating backup program that supports compression and encryption.
Backups are sent to `nas01` (Ubuntu server) via Tailscale.

The passphrase is stored in Bitwarden (**Borg Encryption** item, password field) and deployed
to `/run/bitwarden-secrets/borg_passphrase` at boot by the `bitwarden-secrets-sync` service.

## nas01 Server Setup (one-time)

Clients connect as `scott` via SSH. No separate borg user or forced command is needed —
this is a trusted home network behind Tailscale.

### Step A — Create repo directories

```bash
sudo bash hosts/nas01/config/borg-server-setup.sh
```

This creates `/pool/borg/repos/{latitude,vm01,prodesk,airbook-darwin}` and prints the next steps.

### Step B — Authorize client SSH keys

SSH keys are deployed to `/home/scott/.ssh/` by `apply.sh` (via sops). Add the public keys
to `authorized_keys` so clients can connect:

```bash
grep -qF "$(cat ~/.ssh/id_ed25519_legacy.pub)" ~/.ssh/authorized_keys \
  || cat ~/.ssh/id_ed25519_legacy.pub >> ~/.ssh/authorized_keys
```

All clients use `id_ed25519_legacy` (deployed by bitwarden on NixOS machines, by sops on nas01).

---

## First-Time Setup (new install or rebuild)

Borg will not run successfully until the machine's age key is registered in `.sops.yaml`.
Without it, sops-nix cannot decrypt Bitwarden credentials, so the passphrase is never deployed.

### Step 1 — Get the age key

After first boot (or after `nixos-rebuild switch`):

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
# Output: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 2 — Register the key

On your build machine, add the key to `.sops.yaml`:

```yaml
  - &hostname age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

And add it to the `creation_rules` key group, then re-encrypt:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml
```

### Step 3 — Rebuild and deploy

```bash
sudo nixos-rebuild switch --flake .#<hostname> --target-host scott@<hostname>
```

After rebuild, `bitwarden-secrets-sync` will run on boot and deploy the passphrase.
Verify it landed:

```bash
sudo cat /run/bitwarden-secrets/borg_passphrase
```

### Step 4 — Initialize the repository (first time only)

SSH keys and passphrase are deployed by bitwarden at boot. Once present, initialize
the repo on nas01. Use the key matching the host (see nas01 Server Setup above):

```bash
sudo env \
  BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" \
  BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" \
  borg init --encryption=repokey-blake2 --remote-path=/nix/var/nix/profiles/nas01/bin/borg \
  ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)
```

`--remote-path=/nix/var/nix/profiles/nas01/bin/borg` is required because borg is installed via the
Nix nas01 profile, which is not in PATH for non-login SSH sessions.

### Step 5 — Export and save the repository key

```bash
sudo env \
  BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" \
  BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" \
  borg key export --remote-path=/nix/var/nix/profiles/nas01/bin/borg \
  ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname) \
  ~/borg-key-$(hostname).txt

cat ~/borg-key-$(hostname).txt
```

Save this key in Bitwarden. You need both the key AND the passphrase to restore backups.

### Step 6 — Trigger the first backup

```bash
borg-run
borg-logs
```

## Shell Aliases

All machines have these aliases configured in `shell-aliases.nix`:

| Alias | Description |
|-------|-------------|
| `borg-status` | Show systemd service status |
| `borg-logs` | Show last 50 log lines |
| `borg-timer` | Show next scheduled run |
| `borg-run` | Trigger a manual backup now |
| `borg-list` | List all archives in the repo |
| `borg-info` | Show repo size and stats |
| `borg-check` | Verify repository integrity |
| `borg-unlock` | Break a stale lock (after interrupted backup) |

The `borg-list`, `borg-info`, `borg-check`, and `borg-unlock` aliases automatically set
`BORG_RSH`, `BORG_PASSCOMMAND`, and `BORG_REMOTE_PATH`.

## Restore

```bash
export BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new"
export BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase"
export BORG_REMOTE_PATH=/nix/var/nix/profiles/nas01/bin/borg
REPO="ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname)"

# List archives
sudo -E borg list "$REPO"

# List contents of a specific archive
sudo -E borg list "$REPO::ARCHIVE_NAME"

# Extract a file
sudo -E borg extract "$REPO::ARCHIVE_NAME" home/scott/Documents/important-file.txt

# Extract entire archive
sudo mkdir -p /tmp/restore && cd /tmp/restore
sudo -E borg extract "$REPO::ARCHIVE_NAME"
```

### Mount as filesystem (for browsing)

```bash
export BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new"
export BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase"

sudo mkdir -p /mnt/borg
sudo -E borg mount --remote-path=/nix/var/nix/profiles/nas01/bin/borg \
  ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/$(hostname) \
  /mnt/borg

ls /mnt/borg
sudo borg umount /mnt/borg
```

## Retention Policy

- **Daily**: Keep last 7 days
- **Weekly**: Keep last 4 weeks
- **Monthly**: Keep last 6 months

## Troubleshooting

### Passphrase not deployed

sops-nix couldn't decrypt Bitwarden credentials — the machine's age key is likely
not in `.sops.yaml`. Follow steps 1-3 of First-Time Setup above.

```bash
sudo systemctl status bitwarden-secrets-sync.service
sudo journalctl -u bitwarden-secrets-sync.service -n 30
```

### SSH key missing

```bash
ls -la /home/scott/.ssh/id_ed25519_legacy
sudo systemctl restart bitwarden-secrets-sync.service
```

### Repository locked (interrupted backup)

```bash
borg-unlock
```

### Reset a corrupted repo on nas01

```bash
ssh scott@nas01.warthog-royal.ts.net 'rm -rf /pool/borg/repos/<hostname>'
# Then re-run Step 4 above
```

## Module Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Borg backup service |
| `repository` | — | Repository URL (required) |
| `paths` | `["/home"]` | Paths to back up |
| `exclude` | (various caches) | Patterns to exclude |
| `encryption.mode` | `repokey-blake2` | Encryption mode |
| `encryption.passphraseFile` | `null` | Path to passphrase file |
| `sshKeyFile` | `null` | SSH private key for remote repos |
| `remotePath` | `/nix/var/nix/profiles/nas01/bin/borg` | Path to borg on remote server |
| `schedule` | `daily` | Systemd calendar expression |
| `prune.keep.daily` | `7` | Daily backups to keep |
| `prune.keep.weekly` | `4` | Weekly backups to keep |
| `prune.keep.monthly` | `6` | Monthly backups to keep |

## Security Notes

1. Passphrase lives only in Bitwarden and ephemerally in `/run/bitwarden-secrets/` — never on disk permanently
2. Backups are encrypted with AES-256 (repokey-blake2 mode)
3. The repo key is stored on nas01 but encrypted by the passphrase
4. Without both the repo key export AND the passphrase, backups are unrecoverable — keep both in Bitwarden
5. The borg service waits for `bitwarden-secrets-sync` before running
