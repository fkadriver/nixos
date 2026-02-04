# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

### Build and Apply Configuration
```bash
# Apply configuration to current system (requires sudo)
sudo nixos-rebuild switch --flake .#<hostname>

# Available hostnames: prodesk, latitude, latitude-xfce, latitude-kde,
# latitude-minimal, airbook, airbook-kde

# Examples:
sudo nixos-rebuild switch --flake .#latitude-kde
sudo nixos-rebuild switch --flake .#prodesk
```

### Build VM for Testing
```bash
# Build VM without applying to system
nix build .#nixosConfigurations.<hostname>.config.system.build.vm

# Run the VM
./result/bin/run-<hostname>-nixos-vm

# Example:
nix build .#nixosConfigurations.latitude-xfce.config.system.build.vm
./result/bin/run-latitude-nixos-vm
```

### Build Installer ISO
```bash
# Build bootable installer ISO with automated installation
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# ISO will be in result/iso/
# Write to USB: sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Check Configuration
```bash
# Validate flake configuration
nix flake check
```

### Update Dependencies
```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

## Architecture Overview

### Flake Structure

The repository uses a **flakeContext** pattern where `flake.nix` passes `{ inherit inputs; }` to all modules and host configurations. This allows modules to access flake inputs (nixpkgs, home-manager, disko, sops-nix, etc.) without explicit passing through the module system.

**Module Pattern:**
```nix
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  # Module configuration
  imports = [
    inputs.self.nixosModules.other-module
  ];
}
```

**Host Pattern:**
```nix
{ inputs, ... }@flakeContext:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    inputs.self.nixosModules.common
    ./hardware.nix
    # Additional modules
  ];
}
```

### Module Auto-Discovery

The flake automatically discovers all `.nix` files in `./modules/` and exposes them as `nixosModules.<module-name>`. No need to manually register new modules in `flake.nix`.

**To add a new module:**
1. Create `modules/my-new-module.nix` with the flakeContext pattern
2. Use `inputs.self.nixosModules.my-new-module` to import it

### Module Hierarchy

**Base Module:**
- `common.nix` - Server-safe base configuration (no GUI dependencies)
  - Essential CLI tools, nix settings, docker, direnv
  - Imports: `tailscale.nix`, `shell-aliases.nix`

**Desktop Modules:**
- `desktop-minimal.nix` - KDE Plasma for photo/AI workstations
- `laptop-xfce.nix` - Full XFCE desktop with development tools
- `laptop-kde.nix` - Full KDE Plasma desktop (Windows 11-like)
- `laptop-minimal.nix` - Minimal XFCE for testing

**Utility Modules:**
- `bitwarden.nix` - Secrets management via sops-nix
- `borg-backup.nix` - Encrypted backups to remote servers
- `disko-config.nix` - Automated disk partitioning (1GB boot + LVM)
- `wireless.nix` - WiFi auto-connect for JEN_ACRES network
- `3d-printing.nix` - Orca Slicer, PrusaSlicer, FreeCAD, Blender
- `vscode.nix` - VSCode with gnome-keyring integration
- `syncthing.nix` - File synchronization service
- `tailscale.nix` - VPN with firewall configuration

### Host Configuration Structure

Each host has a base configuration in `hosts/<hostname>/default.nix` with optional variants:
- `kde.nix` - KDE Plasma variant
- `xfce.nix` - XFCE variant
- `minimal.nix` - Minimal testing variant
- `hardware.nix` - Hardware-specific configuration (required)
- `syncthing.nix` - Per-host Syncthing device configuration (optional)

**Current Hosts:**
- **prodesk** - HP ProDesk desktop (photo/AI workstation with disko)
- **latitude** - Dell Latitude 7480 laptop (default: Borg backup + 3D printing)
- **airbook** - MacBook Air 7,2 (Broadcom WiFi requires insecure driver)
- **installer** - Bootable ISO with automated installation script

## Secrets Management with sops-nix

### Initial Setup on New Machine
```bash
# After first build, get the machine's age public key
sudo age-keygen -y /var/lib/sops-nix/key.txt

# Add this key to .sops.yaml under the appropriate machine entry
# Then re-encrypt secrets to include the new machine
sops updatekeys secrets/secrets.yaml
```

### Working with Secrets
```bash
# Edit encrypted secrets file
sops secrets/secrets.yaml

# Extract from Bitwarden (requires bw CLI and BW_SESSION)
export BW_SESSION=$(bw unlock --raw)
bw get item "GitHub SSH Key" | jq -r '.notes'
bw get password "WiFi Password"

# Re-encrypt after adding new machine keys to .sops.yaml
# IMPORTANT: Set SOPS_AGE_KEY_FILE first or sops will fail
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml
```

### Secrets in Modules
Reference secrets via `config.sops.secrets."path/to/secret".path` in NixOS modules. SSH keys are automatically deployed when configured in `services.bitwarden-secrets.sshKeys`.

## Disko and Installation

### Automated Installation with Installer ISO
1. Boot from installer ISO (built with `nix build .#nixosConfigurations.installer.config.system.build.isoImage`)
2. Run `/etc/nixos-install-helper.sh`
3. Script will:
   - Prompt for git repository URL
   - Dynamically discover available configurations
   - Partition disk with disko (1GB boot + LVM with 8GB swap + root)
   - Install NixOS directly from GitHub

### Manual Installation with Disko
```bash
# 1. Partition disk (fetches from GitHub, no cloning needed)
sudo nix run github:nix-community/disko -- \
  --mode disko \
  --flake github:fkadriver/nixos#<hostname> \
  --arg device '"/dev/sdX"'

# 2. Install NixOS
sudo nixos-install --flake github:fkadriver/nixos#<hostname>

# 3. Reboot
sudo reboot
```

## Hardware-Specific Notes

### MacBook Air 7,2 (airbook)
- **WiFi**: Uses Broadcom BCM43xx with broadcom-sta driver (insecure, marked with CVEs)
- **CPU**: Intel Core i5-5250U/i7-5650U (Broadwell)
- Module explicitly permits insecure packages for hardware compatibility

### HP ProDesk (prodesk)
- **Purpose**: Minimal photo processing and AI workstation
- **Optimized for**: photoAlbumOrganizer (OpenCV, dlib, face_recognition)
- **Desktop**: Lightweight KDE Plasma 6
- **No Borg backup configured** (not a primary system)

### Dell Latitude 7480 (latitude)
- **Default config**: Includes Borg backup and 3D printing support
- **Logitech support**: Mouse button tools (xdotool, xbindkeys)

## Common Development Tasks

### Adding a New Host Configuration
See `docs/adding-hosts.md` for comprehensive guide. Quick steps:
1. Create `hosts/<hostname>/` directory
2. Add `default.nix` (imports modules) and `hardware.nix` (hardware-configuration.nix)
3. Add entry to `flake.nix` nixosConfigurations
4. Generate age key after first build and add to `.sops.yaml`
5. Run `sops updatekeys secrets/secrets.yaml` to grant access to secrets

### Adding a New Module
1. Create `modules/<module-name>.nix` using flakeContext pattern
2. Module is auto-discovered, no flake.nix changes needed
3. Import in hosts via `inputs.self.nixosModules.<module-name>`

### Testing Configuration Changes
Always test in VM before applying to hardware:
```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.vm
./result/bin/run-<hostname>-nixos-vm
```

### Boot Menu Configuration
Boot labels are set via `boot.loader.systemd-boot.label` or `boot.loader.grub.entryOptions`. Examples:
- "KDE" - KDE Plasma variant
- "XFCE" - XFCE variant
- "XFCE-minimal" - Minimal testing configuration

### Garbage Collection
The configuration automatically:
- Runs garbage collection weekly (keeps last 30 days)
- Keeps only 10 boot menu generations
- Configured in `common.nix`

## Important Notes

- **Flake inputs tracking**: Uses nixpkgs-unstable (not stable channel)
- **All hosts use disko**: Automated disk partitioning with 1GB boot + LVM
- **Broadcom WiFi**: MacBook Air requires insecure broadcom-sta driver
- **Secrets are in git**: Encrypted with sops-nix using age keys
- **No manual filesystem config**: All disk layouts are declarative via disko
- **Home Manager**: Configured for user "scott" in `homeConfigurations/scott.nix`
