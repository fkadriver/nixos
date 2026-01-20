# NixOS Flake Configuration

A modular NixOS configuration for laptops and servers with automated installation support via disko.

## Supported Configurations

### Laptops
- **latitude**: Dell Latitude 7480 (XFCE) - Primary configuration with Borg backup, 3D printing
- **latitude-xfce**: Dell Latitude 7480 with full applications (XFCE)
- **latitude-kde**: Dell Latitude 7480 with KDE Plasma (Windows 11-like taskbar)
- **latitude-minimal**: Dell Latitude 7480 minimal testing configuration (XFCE)
- **airbook**: Apple MacBook Air 7,2 (13-inch, Early 2015/Mid 2017) (XFCE)
- **airbook-kde**: Apple MacBook Air 7,2 with KDE Plasma

### Installer
- **installer**: Bootable ISO with automated disk partitioning and installation

## Module Architecture

### Core Modules

#### common.nix
Server-compatible base configuration that can be used on any machine, including servers without a GUI.

**Features:**
- Essential CLI tools (git, vim, htop, jq, tmux, etc.)
- Nix flakes enabled
- Docker virtualization
- Direnv integration
- Locale and timezone settings (US Central Time)

**Includes:**
- `tailscale.nix` - Tailscale VPN with firewall configuration
- `syncthing.nix` - File synchronization service
- `shell-aliases.nix` - Common command aliases

### Laptop Modules

#### laptop-xfce.nix
Full-featured XFCE desktop configuration.

**Desktop Environment:**
- XFCE Desktop Environment
- LightDM display manager
- Boot label: "XFCE"

**Features:**
- Development tools (VSCodium, Claude Code, Python)
- Gaming support (Heroic, Lutris, Wine)
- Media tools (Shotwell)
- Office suite (LibreOffice, Thunderbird)
- Firefox browser
- nix-ld for running non-NixOS binaries
- Mouse button tools (xdotool, xbindkeys) for Logitech mice

**Includes:**
- `3d-printing.nix` - UltiMaker Cura, PrusaSlicer, FreeCAD, Blender
- `vscode.nix` - VSCode with gnome-keyring integration
- `wireless.nix` - WiFi configuration

#### laptop-kde.nix
KDE Plasma desktop configuration with Windows 11-like experience.

**Desktop Environment:**
- KDE Plasma 6
- SDDM display manager (Wayland)
- Boot label: "KDE"

**Features:**
- Windows 11-like taskbar (can be cloned to all monitors)
- Development tools (VSCodium, Claude Code, Python)
- Gaming support (Heroic, Lutris, Wine)
- KDE applications (Dolphin, Konsole, Kate, Gwenview)
- KDE Connect for phone integration
- PipeWire audio

**Includes:**
- `3d-printing.nix` - UltiMaker Cura, PrusaSlicer, FreeCAD, Blender
- `vscode.nix` - VSCode with gnome-keyring integration
- `wireless.nix` - WiFi configuration

#### laptop-minimal.nix
Minimal XFCE configuration for testing.

**Desktop Environment:**
- Basic XFCE Desktop Environment
- LightDM display manager
- Boot label: "XFCE-minimal"

**Features:**
- Minimal applications (VSCodium, Claude Code, Python, Firefox)
- No gaming tools
- No Bitwarden integration
- No WiFi auto-configuration

### Utility Modules

#### wireless.nix
WiFi network configuration for JEN_ACRES network.

**Features:**
- Auto-connect configuration for JEN_ACRES WiFi
- WPA-PSK security
- IPv4 and IPv6 auto-configuration

**Usage:**
Automatically imported by all laptop profiles (except laptop-minimal).

#### shell-aliases.nix
System-wide shell aliases for common commands.

**Aliases:**
- `nas01` - SSH to nas01 via Tailscale
- `slap` - SSH to latitude via Tailscale
- `log01` - SSH to sands-log01 via Tailscale
- `gpc` - Grep with color output

#### bitwarden.nix
Secrets management module with sops-nix integration.

**Features:**
- Encrypted secrets in git repository
- Integration with Bitwarden CLI
- Automatic SSH key deployment
- Per-user and per-service secrets
- Automatic service restarts on secret changes

**Supported Secrets:**
- SSH keys
- Tailscale auth keys
- WiFi passwords
- API keys and service credentials

#### disko-config.nix
Automated disk partitioning configuration using disko.

**Partition Scheme:**
- 1 GB `/boot` partition (EFI/FAT32)
- LVM on remaining space:
  - 8 GB swap partition
  - Rest of space for root (`/`) filesystem (ext4)

**Features:**
- Declarative disk configuration
- Supports automated installation
- Resumable hibernation support
- `noatime` mount option for improved performance

**Usage:**
Automatically applied during installer ISO installation.
Can be customized per-host by overriding the `disko.devices.disk.main.device` option.

#### borg-backup.nix
Borg backup configuration for automated encrypted backups.

**Features:**
- Encrypted backups (repokey-blake2)
- SSH transport to remote servers
- Automatic pruning with configurable retention
- Systemd timer for scheduled backups

**Configuration Options:**
- Repository path (local or SSH)
- Backup paths and exclusions
- Pruning schedule (daily, weekly, monthly retention)
- Schedule (daily, weekly, or custom)

#### 3d-printing.nix
3D printing software for Creality Ender 3 V3 KE and other printers.

**Included Software:**
- UltiMaker Cura 5.7.1 (AppImage with desktop integration)
- PrusaSlicer
- FreeCAD
- Blender
- OpenSCAD
- MeshLab

#### syncthing.nix
File synchronization service configuration.

**Settings:**
- User: scott
- Data directory: /home/scott
- Devices and folders can be configured via Syncthing UI

#### tailscale.nix
Tailscale VPN configuration with firewall rules.

**Features:**
- Tailscale interface trusted in firewall
- DNS over TLS (opportunistic)
- DNSSEC (allow-downgrade)
- Routing features enabled

#### user-scott.nix
User account configuration for scott.

**Settings:**
- Member of: wheel, networkmanager, docker
- Hashed password configured

## Building and Installation

### Build NixOS Configuration

```bash
# For Dell Latitude 7480 with XFCE (default)
sudo nixos-rebuild switch --flake .#latitude

# For Dell Latitude 7480 with full XFCE
sudo nixos-rebuild switch --flake .#latitude-xfce

# For Dell Latitude 7480 with KDE Plasma
sudo nixos-rebuild switch --flake .#latitude-kde

# For Dell Latitude 7480 minimal testing
sudo nixos-rebuild switch --flake .#latitude-minimal

# For MacBook Air 7,2 with XFCE
sudo nixos-rebuild switch --flake .#airbook

# For MacBook Air 7,2 with KDE Plasma
sudo nixos-rebuild switch --flake .#airbook-kde
```

### Build Automated Installer ISO (Recommended)

The installer ISO includes disko for automated disk partitioning and a menu-driven installation process:

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

The ISO will be in `result/iso/`. To write to a USB drive:

```bash
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

**Important:** Replace `/dev/sdX` with your actual USB drive device.

### Using the Automated Installer

1. **Boot from the USB drive**
   - Select the NixOS installer from your boot menu

2. **Run the installation script**
   ```bash
   /etc/nixos-install-helper.sh
   ```

   Note: The script is located in `/etc/`, not in the home directory.

3. **Follow the prompts:**
   - Enter git repository URL (e.g., `github:fkadriver/nixos`)
   - Select configuration (latitude, airbook, or nas01)
   - Choose target disk
   - Confirm installation

The installer will automatically:
- Connect to WiFi (JEN_ACRES network pre-configured)
- Partition the disk using disko (1GB /boot + LVM with 8GB swap + root)
- Install NixOS directly from the git repository
- Offer to reboot

Note: The installer fetches the configuration directly from git, no cloning needed.

### Manual Installation with Disko

If you prefer manual installation:

```bash
# 1. Partition the disk (using git flake directly)
sudo nix run github:nix-community/disko -- \
  --mode disko \
  --flake github:fkadriver/nixos#latitude \
  --arg device '"/dev/sdX"'

# 2. Install NixOS (directly from git, no cloning needed)
sudo nixos-install --flake github:fkadriver/nixos#latitude

# 4. Reboot
sudo reboot
```

Replace `<configuration>` with: `latitude`, `airbook`, or `nas01`.

### Test Configuration in VM

Before installing on hardware, you can test configurations in a virtual machine:

```bash
# Build and run VM for Dell Latitude 7480 with XFCE
nix build .#nixosConfigurations.latitude-xfce.config.system.build.vm
./result/bin/run-latitude-nixos-vm

# Build and run VM for MacBook Air 7,2
nix build .#nixosConfigurations.airbook.config.system.build.vm
./result/bin/run-airbook-nixos-vm
```

**VM Notes:**
- VM will open in a QEMU window
- Login with user `scott` and the configured password
- VM state is stored in the current directory (delete `*.qcow2` files to reset)
- Press `Ctrl+Alt+G` to release mouse from VM window
- Close window or run `poweroff` inside VM to shutdown

### Check Configuration

```bash
nix flake check
```

## Boot Menu Labels

The boot menu will display configurations with clear labels:
- **XFCE** - Full XFCE desktop with all applications
- **KDE** - KDE Plasma desktop (Windows 11-like)
- **XFCE-minimal** - Minimal XFCE for testing

## Network Configuration

### WiFi

The JEN_ACRES WiFi network is configured to auto-connect in all full laptop profiles via the `wireless.nix` module. To add additional networks:

1. Use NetworkManager's `nmtui` or `nmcli` tools
2. Or add additional profiles to `wireless.nix` following the JEN_ACRES pattern

### Tailscale

Tailscale is enabled by default. After first boot:

```bash
sudo tailscale up
```

Then authenticate via the provided URL.

## Hardware-Specific Notes

### MacBook Air 7,2

**WiFi:** Uses Broadcom BCM43xx chipset with broadcom-sta driver (wl module).

**Security Notice:** The broadcom-sta driver has known CVEs (CVE-2019-9501, CVE-2019-9502) and is marked as insecure. The configuration explicitly permits this package for hardware compatibility. Consider alternative WiFi hardware for better security.

**CPU:** Intel Core i5-5250U or i7-5650U (Broadwell architecture)

### Dell Latitude 7480

**Additional Features:**
- Logitech wireless peripheral support with GUI tools

## Directory Structure

```
.
├── flake.nix                      # Main flake configuration (auto-discovers modules)
├── hosts/
│   ├── latitude/
│   │   ├── default.nix            # Dell Latitude 7480 (XFCE, Borg backup, 3D printing)
│   │   ├── hardware.nix           # Hardware configuration
│   │   ├── syncthing.nix          # Syncthing device config
│   │   ├── minimal.nix            # Minimal testing configuration
│   │   ├── xfce.nix               # XFCE full configuration
│   │   └── kde.nix                # KDE Plasma configuration
│   ├── airbook/
│   │   ├── default.nix            # MacBook Air 7,2 configuration
│   │   ├── hardware.nix           # Hardware configuration
│   │   ├── syncthing.nix          # Syncthing device config
│   │   ├── bluetooth.nix          # Bluetooth configuration
│   │   └── kde.nix                # KDE Plasma configuration
│   └── installer/
│       └── default.nix            # Automated installer ISO
├── modules/                       # Auto-discovered by flake.nix
│   ├── common.nix                 # Base configuration (server-safe)
│   ├── laptop-xfce.nix            # XFCE laptop configuration
│   ├── laptop-kde.nix             # KDE Plasma laptop configuration
│   ├── laptop-minimal.nix         # Minimal testing configuration
│   ├── 3d-printing.nix            # Cura, PrusaSlicer, FreeCAD, Blender
│   ├── borg-backup.nix            # Encrypted backup to remote servers
│   ├── bitwarden.nix              # Secrets management
│   ├── wireless.nix               # WiFi configuration
│   ├── disko-config.nix           # Automated disk partitioning
│   ├── shell-aliases.nix          # System-wide aliases
│   ├── syncthing.nix              # File synchronization
│   ├── tailscale.nix              # VPN configuration
│   ├── vscode.nix                 # VSCode with gnome-keyring
│   └── user-scott.nix             # User account
├── archive/                       # Archived/unused configurations (see archive/README.md)
│   ├── modules/                   # Hyprland, iDrive e360 modules
│   ├── hosts/                     # Archived host configs
│   └── pkgs/                      # Archived packages
└── docs/
    ├── borg-backup.md             # Borg backup setup and usage
    ├── bitwarden-secrets-setup.md # Comprehensive secrets guide
    └── bitwarden-examples.nix     # Example configurations
```

## Borg Backup

Borg backup is configured for encrypted backups to a remote server via SSH. See [docs/borg-backup.md](docs/borg-backup.md) for detailed setup and usage instructions.

### Quick Start

```bash
# Initialize the repository (first time only)
sudo borg init --encryption=repokey-blake2 ssh://user@server/path/to/repo

# Create passphrase file
echo "your-passphrase" | sudo tee /etc/borg-passphrase
sudo chmod 600 /etc/borg-passphrase

# Manual backup
sudo systemctl start borgbackup-job-system

# Check backup status
sudo systemctl status borgbackup-job-system
```

## Bitwarden Secrets Management

Manage SSH keys, Tailscale auth keys, WiFi passwords, and other secrets using Bitwarden and sops-nix.

### Quick Start

1. **Enable in your host configuration:**

   ```nix
   services.bitwarden-secrets = {
     enable = true;
     secretsFile = ../secrets/secrets.yaml;

     # SSH keys to install
     sshKeys = {
       id_ed25519 = {
         user = "scott";
         secretName = "ssh/github_key";
       };
     };
   };
   ```

2. **Generate age key (done automatically on first build):**

   ```bash
   # Get your public key after build
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```

3. **Create .sops.yaml:**

   ```yaml
   keys:
     - &admin age1xxxxxxxxxxxxxx  # Your public key

   creation_rules:
     - path_regex: secrets/secrets\.yaml$
       key_groups:
         - age:
             - *admin
   ```

4. **Create and encrypt secrets:**

   ```bash
   # Create secrets template
   cat > secrets/secrets.yaml <<EOF
   tailscale:
     auth_key: tskey-auth-xxxxx

   ssh:
     github_key: |
       -----BEGIN OPENSSH PRIVATE KEY-----
       YOUR_KEY_HERE
       -----END OPENSSH PRIVATE KEY-----

   wifi:
     home: your_wifi_password
   EOF

   # Encrypt with sops
   sops -e -i secrets/secrets.yaml
   ```

5. **Extract from Bitwarden:**

   ```bash
   # Login to Bitwarden
   export BW_SESSION=$(bw unlock --raw)

   # Get secrets
   bw get item "GitHub SSH Key" | jq -r '.notes'
   bw get password "WiFi Password"

   # Edit encrypted file
   sops secrets/secrets.yaml
   ```

### Supported Secrets

- **SSH Keys**: Automatically installed to `~/.ssh/`
- **Tailscale Auth Keys**: Reference with `config.sops.secrets."tailscale/auth_key".path`
- **WiFi Passwords**: Use in NetworkManager profiles
- **API Keys**: Any service requiring secrets
- **Custom Secrets**: Define in `sops.secrets`

### Documentation

- **Comprehensive Setup Guide**: [docs/bitwarden-secrets-setup.md](docs/bitwarden-secrets-setup.md) - Step-by-step instructions for setting up sops-nix with Bitwarden
- **Example Configurations**: [docs/bitwarden-examples.nix](docs/bitwarden-examples.nix) - 10 practical examples for common use cases
- **Quick Reference**: [docs/SECRETS-QUICKREF.md](docs/SECRETS-QUICKREF.md) - Command cheat sheet for daily use

### Key Features

✅ Encrypted secrets in git repository
✅ Integration with Bitwarden CLI
✅ Automatic SSH key deployment
✅ Per-user and per-service secrets
✅ Automatic service restarts on secret changes
✅ Multi-machine support with different keys

## Future Enhancements

- **Home Manager Integration**: For user-specific configuration management
- **Additional Hardware**: Add support for more hardware configurations

## Contributing

This is a personal NixOS configuration. Feel free to use it as inspiration for your own setup.

## License

This configuration is provided as-is for personal use.

## Acknowledgments

- Inspired by [Fortydeux-NixOS-System-Flake](https://github.com/WhatstheUse/Fortydeux-NixOS-System-Flake)
- Inspired by [hyprvibe](https://github.com/ChrisLAS/hyprvibe)
- Based on https://mynixos.com/fkadriver/Driver
