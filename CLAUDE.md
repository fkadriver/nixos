# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

### Build and Apply Configuration
```bash
# Apply configuration to current system (requires sudo)
sudo nixos-rebuild switch --flake .#<hostname>

# Available NixOS hostnames: latitude, latitude-xfce,
# latitude-minimal, airbook, airbook-xfce, OTworkstation, vm01, nas01, log01, pihole01, pihole02
# Note: latitude-kde merged into latitude; latitude-minimal kept as fallback
# Variants share a hostname (airbook/airbook-xfce, latitude/latitude-xfce), so
# check which one is running before rebuilding: cat /etc/nixos-flake-attr
# (set for every config in flake.nix; nix-rebuild and nix-sync use it).

# Examples:
sudo nixos-rebuild switch --flake .#latitude
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

**Desktop Modules** (the unused `desktop-minimal.nix` and the paused Nebula
modules `dnclient.nix`/`nebula.nix` are in `archive/modules/`; see
`docs/nebula.md` for the Nebula resume path):
- `laptop-xfce.nix` - Full XFCE desktop with development tools
- `laptop-kde.nix` - Full KDE Plasma desktop (Windows 11-like)
- `laptop-minimal.nix` - Minimal XFCE for testing

**Utility Modules:**
- `bitwarden.nix` - Secrets management via sops-nix
- `borg-backup.nix` - Encrypted backups to remote servers
- `disko-config.nix` - Automated disk partitioning (1GB boot + LVM)
- `wireless.nix` - WiFi auto-connect for JEN_ACRES network
- `3d-printing.nix` - OrcaSlicer, FreeCAD, OpenSCAD, Blender, MeshLab, SolveSpace, f3d
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
- **airbook** - MacBook Air 7,2 back on NixOS after a forced macOS Tahoe upgrade (2026-11-20); Broadcom `wl` driver; uses the airbook-darwin Syncthing device name (kept from its macOS days). Default is KDE Plasma 6 (since 2026-11-26, previously the `airbook-kde` variant); `airbook-xfce` is the XFCE + Plank variant; shared config lives in `hosts/airbook/base.nix`. The old nix-darwin `airbook-darwin` config was deleted on 2026-11-26 (last present in commit `2ef6a2e`); its borg repo `/pool/borg/airbook-darwin` stays on nas01 as a cold copy that can be deleted if space runs low
- **OTworkstation** - Dell Latitude 5480 (OT lab VM workstation, XFCE minimal, VMware + VirtualBox)
- **vm01** - Dell Latitude E7270 (Service Tag: 7NYTSF2, Immich app + Postgres — library data lives on nas01 via NFS)
- **nas01** - NAS server (ZFS raidz1 pool, NFS incl. Immich library export, Borg backup server, Syncthing hub, IDrive360 in Docker; converted from Ubuntu — see docs/nas01.md)
- **log01** - Shuttle Zingbox GL014G128W10, 128GB SSD (syslog collector — rsyslog UDP/TCP 514)
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

**NixOS Systems:**
- Use `bitwarden-scott.nix` module which configures `services.bitwarden.sshKeys` to fetch SSH keys from Bitwarden during system activation
- Other secrets (Tailscale auth keys, WiFi passwords, etc.) are stored encrypted in `secrets.yaml` and deployed via sops-nix
- Reference sops secrets via `config.sops.secrets."path/to/secret".path`

**What's in secrets.yaml:**
- **SSH keys** under the `ssh/` prefix (used by the archived airbook-darwin config)
- Bitwarden login credentials (for the bitwarden CLI on NixOS)
- Service secrets (Tailscale auth keys, WiFi passwords, etc.)

## Disko and Installation

### Staged Installation (preferred)
Install `<host>-bootstrap` from the ISO (small, fully cached base system), run
`bootstrap-join` on the host (joins Tailscale as tag:device), then run
`scripts/enroll-host.sh <host>` on latitude (enrolls the sops age key, pins the
SSH host key, builds the full config using the nas01 cache proxy and fleet
peers). Full walkthrough: `docs/installing.md`. Bootstrap configs are generated
in `flake.nix` from `bootstrapHardware` + `modules/bootstrap.nix`.

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
# Not `--flake ... --arg device`: disko ignores --arg with --flake, so the
# layout's /dev/sda default would be wiped instead. The override file is on
# the installer ISO; elsewhere use hosts/installer/disko-device-override.nix
# from a clone.
sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  --argstr flakeRef github:fkadriver/nixos \
  --argstr config <hostname> \
  --argstr device /dev/sdX \
  /etc/disko-device-override.nix

# 2. Install NixOS
sudo nixos-install --flake github:fkadriver/nixos#<hostname>

# 3. Reboot
sudo reboot
```

## Hardware-Specific Notes

### Dell Latitude 7480 (latitude)
- **Service Tag**: 3BLBPQ2
- **Default config**: Includes Borg backup and 3D printing support
- **Logitech support**: Mouse button tools (xdotool, xbindkeys)
- **Kali Linux**: headless Kali in a Docker container via the `kali` wrapper command
  (`modules/kali-docker.nix`, imported by `daily-driver.nix`) — same image and
  interface as the archived airbook-darwin setup, no VM layer needed since Docker already runs
  natively here. See `docs/kali-docker.md`.
- **Home Assistant**: no official Linux client, so `daily-driver.nix` installs
  the community companion agent `go-hass-agent` plus two desktop entries ("Home
  Assistant Agent", "Home Assistant" dashboard in Firefox). The
  `systemd.user.services.go-hass-agent` unit registers the agent at login with
  the long-lived token in sops (`home-assistant/agent_token`, shared by all
  daily drivers) unless `preferences.toml` already says `registered = true`,
  then runs it. Manual equivalent: `go-hass-agent register --force --server
  https://homeassistant.warthog-royal.ts.net --token <token>`.

### Dell Latitude E7270 (vm01)
- **Purpose**: Immich app + Postgres (frontend/database only — library data lives on nas01)
- **Service Tag**: 7NYTSF2
- **Library storage**: NFS-mounted from nas01 (`/pool/photos` → `/mnt/nas01/immich-library`, lazy-automount); no dedicated `immich` system user — compose checkout lives under scott's home, container runs as PUID/PGID 991:989 (nas01's immich uid/gid)
- **Database**: Local Postgres under the compose checkout (not on NFS — Postgres doesn't tolerate NFS-backed data dirs)
- **Features**: Borg backup to nas01, wireless, docker
- **Note**: Headless server, no desktop environment. The old 1TB USB drive at `/mnt/immich` was removed (failing hardware) as part of this migration.

### Immich fleet (vm01 + nas01 + latitude)
Distributed across three hosts: **vm01** runs the app + Postgres + Redis,
**nas01** hosts the library data (NFS export only, no containers), and
**latitude** runs the machine-learning worker (OpenVINO). Compose stacks and
fleet-management scripts live in their own GitHub repos, not here (they're
not referenced by nix code, so they don't belong in this flake):
- `immich-app` (vm01): app compose stack, `immich-fleet-status.sh`,
  `immich-fleet-check.sh`, `immich-fleet-update.sh` (update ML + app/db with
  one command, in the right order)
- `immich_machine_learning` (latitude): ML compose stack, `immich-update.sh`

Run `immich-fleet-update.sh` from vm01 (or anywhere with SSH access to the
fleet) to update every component — pulls latest images and restarts ML
first, then app/db, stopping before touching the app if ML fails.

### Work MacBook (not part of this flake)
A separate, non-Nix work MacBook mirrors the terminal *look* of
`airbook-darwin` — same starship prompt layout and the Dracula ("vampire")
iTerm2 color profile — via a plain Homebrew + dotfiles bootstrap script
(`starship.toml`, `.tmux.conf`, a marked block in `.zshrc`, and the Dracula
iTerm2 Dynamic Profile JSON from the deleted airbook-darwin `home.nix`). Deliberately
excludes Nix/nix-darwin and every home-infra-specific alias (Tailscale SSH
shortcuts, borg, IDrive360) since it's a work device, not part of this
personal flake. The script isn't checked into this repo (it was handed to the
user directly); the source of truth if it needs to be regenerated is the
airbook-darwin config in git history: `git show 2ef6a2e:hosts/airbook-darwin/home.nix`.

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
- Runs garbage collection weekly (keeps last 7 days of generations, then GCs unreferenced store paths)
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
