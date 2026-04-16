# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

### Build and Apply Configuration
```bash
# Apply configuration to current system (requires sudo)
sudo nixos-rebuild switch --flake .#<hostname>

# Available NixOS hostnames: latitude, latitude-xfce,
# latitude-minimal, vm01, pihole01, pihole02
# Note: latitude-kde merged into latitude; latitude-minimal kept as fallback

# Examples:
sudo nixos-rebuild switch --flake .#latitude

# macOS (nix-darwin) - requires sudo for system changes
sudo darwin-rebuild switch --flake .#airbook-darwin
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
  - Essential CLI tools, nix settings, docker, direnv, tmux
  - Tmux auto-starts for interactive bash sessions (skips VS Code terminals)
  - Git configured with user.name/email for all systems
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
- `3d-printing.nix` - OrcaSlicer, PrusaSlicer, FreeCAD 1.1.0 (nixpkgs 25.11), OpenSCAD, Blender, MeshLab, SolveSpace, f3d, Sweet Home 3D
- `home-design.nix` - Sweet Home 3D for interior design and floor plans (with plugin installer)
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

**Current Hosts (NixOS):**

- **latitude** - Dell Latitude 7480 laptop (default: Borg backup + 3D printing)
- **vm01** - Dell Latitude E7270 (Service Tag: 7NYTSF2, Immich server with external 1TB drive)
- **log01** - Shuttle Zingbox GL014G128W10, 128GB SSD (syslog collector — rsyslog UDP/TCP 514)
- **installer** - Bootable ISO with automated installation script

**Current Hosts (macOS/nix-darwin):**
- **airbook-darwin** - MacBook Air 7,2 running macOS with nix-darwin

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

**NixOS Systems:**
- Use `bitwarden-scott.nix` module which configures `services.bitwarden.sshKeys` to fetch SSH keys from Bitwarden during system activation
- Other secrets (Tailscale auth keys, WiFi passwords, etc.) are stored encrypted in `secrets.yaml` and deployed via sops-nix
- Reference sops secrets via `config.sops.secrets."path/to/secret".path`

**macOS (darwin) Systems:**
- SSH keys are deployed via sops-nix (stored in `secrets.yaml` under `ssh/` prefix)
- The `bitwarden.nix` module is NixOS-specific and doesn't work on darwin
- sops-nix is used for both SSH keys and service secrets
- Age key stored at `/var/root/.config/sops/age/keys.txt` on darwin

**What's in secrets.yaml:**
- **SSH keys** - deployed via sops-nix on darwin systems (stored under `ssh/` prefix)
- Bitwarden login credentials (for the bitwarden CLI on NixOS)
- Service secrets (Tailscale auth keys, WiFi passwords, etc.)
- Note: NixOS systems fetch SSH keys from Bitwarden via `bitwarden.nix` module, while darwin systems get them from `secrets.yaml` via sops-nix

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

## macOS with nix-darwin

### Initial Setup on macOS
```bash
# 1. Install Nix (multi-user installation)
sh <(curl -L https://nixos.org/nix/install)

# 2. Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# 3. Clone the config repository
git clone https://github.com/fkadriver/nixos ~/git/nixos

# 4. Bootstrap nix-darwin (first time only, requires sudo)
sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin -- switch --flake ~/git/nixos#airbook-darwin

# 5. Subsequent rebuilds (also require sudo for system changes)
sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin
```

### Darwin Configuration Structure
- `hosts/airbook-darwin/default.nix` - Main darwin system configuration
- `hosts/airbook-darwin/home.nix` - Home Manager user configuration

### What nix-darwin Manages
- **System packages**: CLI tools installed via Nix (age, sops, htop, go, nodejs, python3)
- **Homebrew**: GUI apps and services
  - Casks: Bitwarden, Firefox, iTerm2, Rectangle, Scroll Reverser, VSCode
  - 3D Printing: OpenSCAD, PrusaSlicer, FreeCAD, Blender, MeshLab, Inkscape
  - Brews: syncthing, bitwarden-cli
- **Fonts**: 3D printing fonts (EB Garamond, Libre Baskerville, Old Standard, Junicode, Inter, Source Sans)
- **macOS settings**: Dock, Finder, keyboard, trackpad, dark mode, Touch ID for sudo
- **Services**: Tailscale VPN, Syncthing (via Homebrew)
- **Home Manager**: Shell config (bash, zsh, starship), VSCode extensions, SSH config, dotfiles
- **Secrets**: SSH keys deployed via sops-nix from encrypted secrets.yaml

### Useful Aliases
- `nix-rebuild` - Runs `cd ~/git/nixos && git pull && sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin; cd -`

### Secrets Management on macOS
After first darwin-rebuild, get the machine's age key:
```bash
# macOS stores the key in a different location than NixOS
sudo age-keygen -y /var/root/.config/sops/age/keys.txt

# Add this key to .sops.yaml, then re-encrypt secrets
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml
```

**Important Notes:**
- SSH keys are **automatically deployed** via sops-nix on macOS
- The `bitwarden.nix` module is NixOS-specific and doesn't work on darwin
- sops-nix deploys both SSH keys and service secrets on darwin
- After `darwin-rebuild`, SSH keys are automatically installed to `~/.ssh/`

## Hardware-Specific Notes

### MacBook Air 7,2 (airbook-darwin)
- **CPU**: Intel Core i5-5250U/i7-5650U (Broadwell)
- **Configuration**: `airbook-darwin` - macOS with nix-darwin (NixOS config archived)
- **macOS config includes**:
  - GUI apps: Bitwarden, Firefox, iTerm2, Rectangle, Scroll Reverser, VSCode
  - Services: Tailscale VPN, Syncthing file sync
  - System settings: Dark mode, Touch ID sudo, dock/keyboard/trackpad preferences
  - Bluetooth: SEENDA keyboard and mouse (manual pairing required)

### Dell Latitude 7480 (latitude)
- **Default config**: Includes Borg backup and 3D printing support
- **Logitech support**: Mouse button tools (xdotool, xbindkeys)

### Dell Latitude E7270 (vm01)
- **Purpose**: Immich photo management server
- **Service Tag**: 7NYTSF2
- **Service User**: `immich` (system user, home: `/opt/immich`, member of `docker` group)
- **External Storage**: 1TB Toshiba drive mounted at `/mnt/immich` (by UUID)
- **Features**: Borg backup to nas01, wireless, docker
- **Note**: Headless server, no desktop environment

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

### Documentation Maintenance
**Before committing changes**, review and update relevant documentation:
- `README.md` - Update if adding hosts or significant features
- `docs/modules.md` - Update when adding/modifying modules
- `docs/hosts.md` - Update when adding/modifying host configurations
- `CLAUDE.md` - Update when changing build commands, architecture, or workflows

This keeps documentation in sync with code changes and helps future development.

## Important Notes

- **Flake inputs tracking**: Uses nixpkgs-unstable (not stable channel)
- **All NixOS hosts use disko**: Automated disk partitioning with 1GB boot + LVM
- **Broadcom WiFi**: MacBook Air NixOS config requires insecure broadcom-sta driver
- **Secrets are in git**: Encrypted with sops-nix using age keys
- **No manual filesystem config**: All disk layouts are declarative via disko
- **Home Manager**: Configured for user "scott" in `homeConfigurations/scott.nix`
- **macOS support**: MacBook Air can run macOS with nix-darwin (`airbook-darwin`)
