# Host Configurations

This document provides a brief overview of all host configurations in this repository.

## NixOS Hosts

### prodesk
**HP ProDesk 600 G4** - Minimal photo/AI workstation

| | |
|---|---|
| Desktop | KDE Plasma 6 (minimal) |
| Purpose | Photo processing, AI/ML development |
| Key Features | Python with OpenCV/dlib, VSCode, disko partitioning |
| Backup | None configured |

### latitude
**Dell Latitude 7480** - Primary laptop (KDE default)

| | |
|---|---|
| Desktop | KDE Plasma (default), XFCE and minimal variants available |
| Purpose | Daily driver development laptop |
| Key Features | Borg backup, 3D printing, Logitech support, multi-monitor |
| Variants | `latitude-xfce`, `latitude-kde`, `latitude-minimal` |

### airbook
**Apple MacBook Air 7,2** (Early 2015/Mid 2017) - NixOS on Mac

| | |
|---|---|
| Desktop | XFCE (default), KDE variant available |
| CPU | Intel Core i5-5250U/i7-5650U (Broadwell) |
| WiFi | Broadcom BCM43xx (requires insecure broadcom-sta driver) |
| Variants | `airbook-kde` |

**Security Note:** The broadcom-sta driver has known CVEs and is marked insecure.

### vm01
**Dell Latitude E7270** - Immich photo server

| | |
|---|---|
| Service Tag | 7NYTSF2 |
| Purpose | Headless Immich photo management server |
| Storage | 1TB Toshiba external drive at `/mnt/immich` |
| Service User | `immich` (home: `/opt/immich`, member of docker group) |
| Key Features | Borg backup to nas01, wireless, docker, VS Code Server |

**Note:** No desktop environment - access via SSH or Tailscale.

### installer
**Bootable ISO** - Automated installation media

| | |
|---|---|
| Purpose | Automated disk partitioning and NixOS installation |
| Features | Disko integration, menu-driven installation, WiFi pre-configured |
| Build | `nix build .#nixosConfigurations.installer.config.system.build.isoImage` |

## macOS Hosts (nix-darwin)

### airbook-darwin
**Apple MacBook Air 7,2** - macOS with nix-darwin

| | |
|---|---|
| Purpose | Declarative macOS package/settings management |
| Homebrew Casks | Bitwarden, Firefox, iTerm2, Rectangle, VSCode, 3D printing apps |
| Services | Tailscale VPN, Syncthing |
| Settings | Dark mode, Touch ID sudo, dock/keyboard/trackpad preferences |

**Rebuild:** `sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin`

## Quick Reference

| Host | Type | Desktop | Primary Use |
|------|------|---------|-------------|
| `prodesk` | Desktop | KDE (minimal) | Photo/AI workstation |
| `latitude` | Laptop | KDE | Daily driver |
| `latitude-xfce` | Laptop | XFCE | Full desktop variant |
| `latitude-kde` | Laptop | KDE | Full desktop variant |
| `latitude-minimal` | Laptop | XFCE | Testing |
| `airbook` | Laptop | XFCE | Mac running NixOS |
| `airbook-kde` | Laptop | KDE | Mac running NixOS |
| `vm01` | Server | None | Immich photo server |
| `installer` | ISO | N/A | Installation media |
| `airbook-darwin` | macOS | N/A | nix-darwin on Mac |

## Building Configurations

```bash
# NixOS
sudo nixos-rebuild switch --flake .#<hostname>

# macOS (nix-darwin)
sudo darwin-rebuild switch --flake .#airbook-darwin

# Build VM for testing
nix build .#nixosConfigurations.<hostname>.config.system.build.vm
./result/bin/run-<hostname>-nixos-vm
```

## Adding New Hosts

See [adding-hosts.md](adding-hosts.md) for a comprehensive guide on adding new machines to this repository.
