# Borg Backup Configuration

This document describes how to set up and use the Borg backup module in this NixOS configuration.

## Overview

Borg Backup is a deduplicating backup program that supports compression and encryption. Backups are sent to `nas01` (Ubuntu server) via Tailscale, ensuring they work from any network.

## Configured Hosts

| Host | Repository | Schedule |
|------|------------|----------|
| latitude | `ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/latitude` | Daily |
| airbook | `ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/airbook` | Daily |

## Server Setup (nas01 - Ubuntu)

The backup server requires:

```bash
# Install borgbackup
sudo apt install borgbackup

# Ensure SSH server is running
sudo systemctl enable ssh
sudo systemctl start ssh
```

## Client Setup (NixOS)

### 1. Create passphrase file on each client

Use the same passphrase for all machines to simplify management:

```bash
# On latitude and airbook
echo "your-secure-passphrase" | sudo tee /etc/borg-passphrase
sudo chmod 600 /etc/borg-passphrase
```

### 2. Initialize the Borg repository (from client, first time only)

This creates the repository directory and initializes it with encryption:

```bash
# On latitude
sudo borg init --encryption=repokey-blake2 \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/latitude

# On airbook
sudo borg init --encryption=repokey-blake2 \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/airbook
```

### 3. Export the repository key (important for recovery!)

```bash
sudo borg key export \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname) \
  ~/borg-key-$(hostname).txt
```

Store this key file securely (e.g., in a password manager). You need both the key and passphrase to restore backups.

## Usage

### Check backup service status

```bash
# View service status
systemctl status borgbackup-job-system.service

# View timer status
systemctl list-timers | grep borg

# View recent logs
journalctl -u borgbackup-job-system.service -n 50
```

### Manual backup

```bash
sudo systemctl start borgbackup-job-system.service
```

### List backups

```bash
sudo borg list ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)
```

### View backup info

```bash
sudo borg info ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)
```

### Restore files

```bash
# List contents of a specific backup
sudo borg list ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)::ARCHIVE_NAME

# Extract specific files to current directory
sudo borg extract \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)::ARCHIVE_NAME \
  home/scott/Documents/important-file.txt

# Extract entire backup to a restore directory
sudo mkdir /tmp/restore
cd /tmp/restore
sudo borg extract \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)::ARCHIVE_NAME
```

### Mount backup as filesystem (for browsing)

```bash
sudo mkdir /mnt/borg
sudo borg mount \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname) \
  /mnt/borg

# Browse backups
ls /mnt/borg

# Unmount when done
sudo borg umount /mnt/borg
```

## Retention Policy

Backups are automatically pruned according to this schedule:

- **Daily**: Keep last 7 days
- **Weekly**: Keep last 4 weeks
- **Monthly**: Keep last 6 months

## What's Backed Up

**Included:**
- `/home/scott` (entire home directory)

**Excluded:**
- `.cache` directories
- `.local/share/Trash`
- `Downloads` folder
- `.npm`, `.cargo`, `.rustup` (package manager caches)
- `node_modules` directories
- Python bytecode (`*.pyc`, `__pycache__`)

## Troubleshooting

### SSH connection issues

Ensure Tailscale is connected:
```bash
tailscale status
ping nas01.warthog-royal.ts.net
```

### Permission denied

The backup runs as root. Ensure the SSH key is accessible:
```bash
sudo ls -la /home/scott/.ssh/id_ed25519
```

### Repository locked

If a backup was interrupted:
```bash
sudo borg break-lock \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)
```

### Check repository integrity

```bash
sudo borg check \
  ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/$(hostname)
```

## Module Options

The `services.borg-backup` module supports these options:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Borg backup service |
| `repository` | - | Repository URL (required) |
| `paths` | `["/home"]` | Paths to back up |
| `exclude` | (various caches) | Patterns to exclude |
| `encryption.mode` | `repokey-blake2` | Encryption mode |
| `encryption.passphraseFile` | `null` | Path to passphrase file |
| `sshKeyFile` | `null` | SSH private key for remote repos |
| `schedule` | `daily` | Systemd calendar expression |
| `prune.keep.daily` | `7` | Daily backups to keep |
| `prune.keep.weekly` | `4` | Weekly backups to keep |
| `prune.keep.monthly` | `6` | Monthly backups to keep |

## Security Notes

1. The passphrase file (`/etc/borg-passphrase`) is readable only by root
2. Backups are encrypted with AES-256 (repokey-blake2 mode)
3. The encryption key is stored in the repository but encrypted with your passphrase
4. **Always keep a backup of your key export and passphrase** - without both, your backups are unrecoverable
