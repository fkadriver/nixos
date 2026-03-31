# Host Configurations

This document provides a brief overview of all host configurations in this repository.

## NixOS Hosts

### latitude
**Dell Latitude 7480** - Primary laptop (KDE default)

| | |
|---|---|
| Desktop | KDE Plasma (default), XFCE and minimal variants available |
| Purpose | Daily driver development laptop |
| Key Features | Borg backup, 3D printing, Logitech support, multi-monitor |
| Variants | `latitude-xfce`, `latitude-kde`, `latitude-minimal` |
| Tailscale tags | `tag:mgmt-admin` (SSH to all infra as scott), `tag:backup-client` (borg to nas01) |

### vm01
**Dell Latitude E7270** - Immich photo server

| | |
|---|---|
| Service Tag | 7NYTSF2 |
| Purpose | Headless Immich photo management server |
| Storage | 1TB Toshiba external drive at `/mnt/immich` |
| Service User | `immich` (home: `/opt/immich`, member of docker group) |
| Key Features | Borg backup to nas01, wireless, docker, VS Code Server |
| Tailscale tags | `tag:backup-client` (borg to nas01), `tag:container` (Immich) |

**Note:** No desktop environment - access via SSH or Tailscale.

### log01
**Shuttle Zingbox GL014G128W10** - Centralized syslog collector

| | |
|---|---|
| Purpose | Centralized syslog server for all NixOS hosts and network devices |
| Storage | 128GB SSD |
| Key Features | rsyslog (UDP/TCP 514), auditd, Borg backup to nas01, Tailscale |
| Log Path | `/var/log/remote/<hostname>/<program>.log` |
| Retention | 30 days (daily logrotate with date suffix) |
| Borg Paths | `/home`, `/var/log` (includes all remote logs) |

**Receiving syslog:** All NixOS hosts with `common.nix` forward to log01 via rsyslog TCP 514 with a disk-assisted queue (survives log01 downtime). Pi-hole hosts also forward FTL DNS query logs via `misc.syslog = true`. `logging.forwardToLog01` is set to `false` on log01 itself to prevent loops.

**Note:** Headless server. No desktop environment. After first boot, get the age key with:
```bash
ssh scott@log01 'sudo age-keygen -y /var/lib/sops-nix/key.txt'
```
Then add to `.sops.yaml` and run `sops updatekeys secrets/secrets.yaml`.

### pihole01
**Raspberry Pi 3B** - Primary Pi-hole DNS server

| | |
|---|---|
| IP | 192.168.10.10 (static) |
| Purpose | Network-wide ad blocking / DNS |
| SoC | BCM2837 (ARM Cortex-A53, aarch64) |
| Key Features | Pi-hole FTL, Hagezi blocklists, Tailscale, sops secrets, rsyslog → log01 |
| Build | `nix build .#nixosConfigurations.pihole01.config.system.build.sdImage` |

**Note:** Cross-compiled from x86_64. Uses `raspberry-pi-nix` modules. No borg backup. DNS query logs forwarded to log01 via rsyslog (FTL syslog enabled).

### pihole02
**Raspberry Pi 3B** - Secondary Pi-hole DNS server

| | |
|---|---|
| IP | 192.168.10.11 (static) |
| Purpose | Redundant DNS / failover for pihole01 |
| SoC | BCM2837 (ARM Cortex-A53, aarch64) |
| Key Features | Pi-hole FTL, Hagezi blocklists, Tailscale, sops secrets, rsyslog → log01 |
| Build | `nix build .#nixosConfigurations.pihole02.config.system.build.sdImage` |

**Note:** Cross-compiled from x86_64. Uses `nixos-hardware` raspberry-pi-3 module. No borg backup. DNS query logs forwarded to log01 via rsyslog (FTL syslog enabled).

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
| `latitude` | Laptop | KDE | Daily driver |
| `latitude-xfce` | Laptop | XFCE | Full desktop variant |
| `latitude-kde` | Laptop | KDE | Full desktop variant |
| `latitude-minimal` | Laptop | XFCE | Testing |
| `vm01` | Server | None | Immich photo server |
| `log01` | Server | None | Syslog collector |
| `pihole01` | RPi 3B | None | Primary Pi-hole DNS |
| `pihole02` | RPi 3B | None | Secondary Pi-hole DNS |
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
