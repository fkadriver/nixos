# NixOS Modules Reference

This document provides a high-level overview of all available modules in this repository.

## Core Modules

| Module | Description |
|--------|-------------|
| `common.nix` | Server-safe base configuration with CLI tools, tmux, git, docker, direnv. Imports `tailscale.nix` and `shell-aliases.nix` |
| `user-scott.nix` | User account configuration (wheel, networkmanager, docker groups) |
| `shell-aliases.nix` | System-wide shell aliases (`nas01`, `slap`, `log01`, `gpc`, rebuild commands) |

## Desktop Environment Modules

| Module | Description |
|--------|-------------|
| `desktop-minimal.nix` | Minimal KDE Plasma 6 for photo/AI workstations with Python/OpenCV/dlib |
| `laptop-xfce.nix` | Full XFCE desktop with development tools, gaming support, media tools |
| `laptop-kde.nix` | Full KDE Plasma 6 with Windows 11-like taskbar, gaming, KDE Connect |
| `laptop-minimal.nix` | Minimal XFCE for testing (no WiFi auto-config, no Bitwarden) |
| `daily-driver.nix` | Shared configuration for Scott's daily-driver machines (applications, fonts, 3D printing) |

## Networking Modules

| Module | Description |
|--------|-------------|
| `tailscale.nix` | Tailscale VPN with firewall rules, DNS over TLS, DNSSEC |
| `wireless.nix` | WiFi auto-connect for JEN_ACRES network (WPA-PSK) |

## Development Modules

| Module | Description |
|--------|-------------|
| `vscode.nix` | VSCode with extensions (Nix, Python, Docker, Claude Code) and gnome-keyring |
| `vscode-server.nix` | VS Code Server for Remote SSH with Claude Code CLI and nix-ld |

## Secrets & Security

| Module | Description |
|--------|-------------|
| `bitwarden.nix` | Generic Bitwarden/sops-nix secrets management module |
| `bitwarden-scott.nix` | Scott-specific Bitwarden SSH key deployment |

## Backup & Sync

| Module | Description |
|--------|-------------|
| `borg-backup.nix` | Encrypted Borg backups to remote servers via SSH |
| `syncthing.nix` | Basic Syncthing file sync service |
| `syncthing-declarative.nix` | Declarative Syncthing with predefined folders/devices |

## Hardware & Peripherals

| Module | Description |
|--------|-------------|
| `logitech.nix` | Logitech device support via Solaar, mouse button tools, NumLock on login |
| `multi-monitor.nix` | Autorandr profiles, custom lid switch handler for docking |
| `autorandr-profiles.nix` | Predefined autorandr display profiles |
| `iphone.nix` | iPhone integration (photo sync, file transfer, device management) |
| `printing.nix` | CUPS printing with Canon LBP162 and Avahi autodiscovery |

## 3D Printing & Design

| Module | Description |
|--------|-------------|
| `3d-printing.nix` | OpenSCAD, PrusaSlicer, FreeCAD, Blender, MeshLab with optional font test generators |
| `home-design.nix` | Sweet Home 3D, LibreCAD, QCAD for home remodeling/deck planning |
| `font.nix` | Modular font management (documents, craft, printing3d, nerd, viewer) |

## Disk & System

| Module | Description |
|--------|-------------|
| `disko-config.nix` | Automated disk partitioning (1GB boot + LVM with 8GB swap + root) |
| `virtualbox.nix` | VirtualBox host with extension pack |

## Module Architecture

All modules use the **flakeContext** pattern:

```nix
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  # Module configuration
}
```

Modules are **auto-discovered** from the `modules/` directory - no need to register them in `flake.nix`. Import them in hosts via:

```nix
inputs.self.nixosModules.<module-name>
```

## Module Options

Some modules provide custom options:

### 3d-printing.nix
- `my.printing.enable` - Core 3D printing tools
- `my.printing.fonts.enable` - 3D-safe emboss fonts
- `my.printing.repairTools` - SVG/STL repair tools
- `my.printing.generateTestArtifacts` - Font test plate/keychain generators

### font.nix
- `my.fonts.documents` - Office/document fonts
- `my.fonts.craft` - Decorative/Cricut fonts
- `my.fonts.printing3d` - 3D printing optimized fonts
- `my.fonts.nerd` - Terminal fonts with Nerd Font glyphs
- `my.fonts.viewer` - Font management tools

### borg-backup.nix
- Repository path, backup paths, exclusions
- Pruning schedule (daily, weekly, monthly retention)
- Schedule configuration
