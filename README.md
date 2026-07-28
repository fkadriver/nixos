# NixOS Flake Configuration

A modular NixOS configuration for laptops and servers with automated installation support via disko.

**Current Release:** NixOS 25.11 "Xantusia" (tracking nixpkgs-unstable)

## Quick Start

```bash
# Apply configuration to current system
sudo nixos-rebuild switch --flake .#<hostname>

# macOS (nix-darwin)
sudo darwin-rebuild switch --flake .#airbook-darwin

# Test in VM before applying
nix build .#nixosConfigurations.<hostname>.config.system.build.vm
./result/bin/run-<hostname>-nixos-vm
```

## Available Configurations

| Host | Hardware | Desktop | Purpose |
|------|----------|---------|---------|
| `latitude` | Dell Latitude 7480 | KDE | Daily driver (Borg backup, 3D printing) |
| `latitude-xfce` | Dell Latitude 7480 | XFCE | Full desktop variant |
| `latitude-kde` | Dell Latitude 7480 | KDE | Full desktop variant |
| `latitude-minimal` | Dell Latitude 7480 | XFCE | Testing |
| `airbook` | MacBook Air 7,2 | XFCE | NixOS on Mac |
| `airbook-kde` | MacBook Air 7,2 | KDE | NixOS on Mac |
| `OTworkstation` | Dell Latitude 5480 | XFCE | OT lab VM workstation |
| `vm01` | Dell Latitude E7270 | Headless | Immich photo server |
| `log01` | Shuttle Zingbox GL014G128W10 | Headless | Centralized syslog collector |
| `nas01` | HP ProDesk 600 G4 DM | Headless | NAS / Borg backup hub |
| `pihole01` | Raspberry Pi 3B | Headless | Primary Pi-hole DNS |
| `pihole02` | Raspberry Pi 3B | Headless | Secondary Pi-hole DNS |
| `installer` | N/A | N/A | Bootable installation ISO |
| `airbook-darwin` | MacBook Air 7,2 | macOS | nix-darwin |

See [docs/hosts.md](docs/hosts.md) for detailed host documentation.

## Directory Structure

```
.
├── flake.nix              # Main flake configuration
├── hosts/                 # Host-specific configurations
│   ├── latitude/         # Dell Latitude 7480 (+ variants)
│   ├── airbook/          # MacBook Air 7,2 NixOS
│   ├── airbook-darwin/   # MacBook Air 7,2 macOS
│   ├── vm01/             # Immich server
│   ├── log01/            # Centralized syslog collector
│   ├── pihole01/         # Primary Pi-hole DNS (RPi 3B)
│   ├── pihole02/         # Secondary Pi-hole DNS (RPi 3B)
│   └── installer/        # Installation ISO
├── modules/               # Auto-discovered NixOS modules
├── secrets/               # Encrypted secrets (sops-nix)
└── docs/                  # Documentation
```

## Module Architecture

Modules are auto-discovered from `modules/` and use the **flakeContext** pattern:

```nix
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [ inputs.self.nixosModules.other-module ];
  # configuration...
}
```

See [docs/modules.md](docs/modules.md) for a complete module reference.

## Installation

### Automated Installation (Recommended)

1. Build the installer ISO:
   ```bash
   nix build .#nixosConfigurations.installer.config.system.build.isoImage
   sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```

2. Boot from USB and run:
   ```bash
   /etc/nixos-install-helper.sh
   ```

3. Follow prompts to select configuration and target disk.

### Manual Installation with Disko

```bash
# Partition disk
sudo nix run github:nix-community/disko -- \
  --mode disko \
  --flake github:fkadriver/nixos#<hostname> \
  --arg device '"/dev/sdX"'

# Install NixOS
sudo nixos-install --flake github:fkadriver/nixos#<hostname>
```

## Secrets Management

Secrets are encrypted with sops-nix using age keys. After first build:

```bash
# Get machine's age public key
sudo age-keygen -y /var/lib/sops-nix/key.txt

# Add key to .sops.yaml, then re-encrypt
sops updatekeys secrets/secrets.yaml
```

See [docs/bitwarden-secrets-setup.md](docs/bitwarden-secrets-setup.md) for comprehensive setup.

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/modules.md](docs/modules.md) | Module reference and options |
| [docs/hosts.md](docs/hosts.md) | Host configuration details |
| [docs/adding-hosts.md](docs/adding-hosts.md) | Adding new machines |
| [docs/borg-backup.md](docs/borg-backup.md) | Backup configuration |
| [docs/bitwarden-secrets-setup.md](docs/bitwarden-secrets-setup.md) | Secrets management |
| [docs/multi-monitor-setup.md](docs/multi-monitor-setup.md) | Display profiles |
| [docs/nixos-binary-compatibility.md](docs/nixos-binary-compatibility.md) | Running non-NixOS binaries |

## Scripts

### deploy-piholes.sh

Deploys NixOS updates to pihole01 and pihole02 sequentially, verifying DNS health after each reboot.

```bash
./scripts/deploy-piholes.sh                        # deploy both; log → /tmp/pihole-update_<ts>.log
./scripts/deploy-piholes.sh pihole01               # deploy one; log → /tmp/pihole01-update_<ts>.log
./scripts/deploy-piholes.sh --build-host vm01      # force build host
./scripts/deploy-piholes.sh --verbose              # full nix build logs on screen + in log file
./scripts/deploy-piholes.sh --quiet                # no log file, minimal screen output
./scripts/deploy-piholes.sh --check-version        # check for newer version on GitHub
```

All output is tee'd to a timestamped log in `/tmp/` by default. Use `--quiet` to suppress logging (errors and final status only). Use `--verbose` to add `--print-build-logs` output.

## Common Tasks

### Check Configuration
```bash
nix flake check
```

### Update Dependencies
```bash
nix flake update                           # Update all inputs
nix flake lock --update-input nixpkgs      # Update specific input
```

### Tailscale Setup
```bash
sudo tailscale up
```

### Borg Backup
```bash
sudo systemctl start borgbackup-job-system  # Manual backup
sudo systemctl status borgbackup-job-system # Check status
```

### Centralized Logging (log01)

All hosts (except log01 itself) forward syslog to `log01` via rsyslog TCP on port 514. Logs are stored at `/var/log/remote/<hostname>/<program>.log` with 30-day retention. Pi-hole DNS query logs (FTL) are included via `misc.syslog = true`.

```bash
# View logs from a specific host on log01
tail -f /var/log/remote/<hostname>/pihole-FTL.log

# Check rsyslog forwarding status on any host
sudo systemctl status rsyslog
```

## Hardware Notes

- **MacBook Air 7,2 (airbook-darwin)**: Now running macOS via nix-darwin. Broadcom WiFi driver is only included in the installer ISO (needed to get WiFi during NixOS installation on this hardware).
- **vm01**: Headless server with 1TB external drive at `/mnt/immich`

## Logitech Device Management

Logitech devices on `latitude` are managed by [Solaar](https://github.com/pwr-Solaar/Solaar) via `modules/logitech.nix`. [OpenLogi](https://openlogi.org) is a promising telemetry-free alternative but is currently macOS-only (Linux support is on their roadmap — check back before the next major Solaar update).

## Shell Aliases

Defined in `modules/shell-aliases.nix`:
- `nix-rebuild` - Pull latest and rebuild current host (NixOS) or darwin (airbook)
- `nix-sync` - Run `scripts/sync-nixos-hosts.sh`
- `smart [drive]` - Full SMART report for all drives, or just one (e.g. `smart sda`)
- `ts-info [host]` - Show enabled Tailscale features (SSH, exit-node option, routes, tags) for self, or a peer by hostname

## Acknowledgments

- Inspired by [Fortydeux-NixOS-System-Flake](https://github.com/WhatstheUse/Fortydeux-NixOS-System-Flake)
- Inspired by [hyprvibe](https://github.com/ChrisLAS/hyprvibe)
- Inspired by [mkellyxp/nixbook](https://github.com/mkellyxp/nixbook)
