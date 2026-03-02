# NixOS Flake Configuration

A modular NixOS configuration for laptops and servers with automated installation support via disko.

**Current Release:** NixOS 25.11 "Xantusia" (tracking nixpkgs-unstable)

## Supported Configurations

### Desktops
- **prodesk**: HP ProDesk - Minimal desktop for photo and AI processing (KDE Plasma)

### Laptops
- **latitude**: Dell Latitude 7480 (KDE) - Primary configuration with Borg backup, 3D printing
- **latitude-xfce**: Dell Latitude 7480 with full applications (XFCE)
- **latitude-kde**: Dell Latitude 7480 with KDE Plasma (Windows 11-like taskbar)
- **latitude-minimal**: Dell Latitude 7480 minimal testing configuration (XFCE)
- **airbook**: Apple MacBook Air 7,2 (13-inch, Early 2015/Mid 2017) (XFCE)
- **airbook-kde**: Apple MacBook Air 7,2 with KDE Plasma

### Servers
- **vm01**: Dell Latitude E7270 - Immich photo server with external 1TB storage

### Installer
- **installer**: Bootable ISO with automated disk partitioning and installation

## Module Architecture

### Core Modules

#### common.nix
Server-compatible base configuration that can be used on any machine, including servers without a GUI.

**Features:**
- Essential CLI tools (git, vim, htop, btop, jq, ripgrep, etc.)
- Tmux terminal multiplexer with auto-start for bash sessions
- Git configured globally (user.name, user.email)
- Nix flakes enabled
- Docker virtualization
- Direnv integration
- Locale and timezone settings (US Central Time)

**Tmux Configuration:**
- Auto-starts for interactive bash sessions (creates/attaches to "default" session)
- Skips auto-start in VS Code terminals, existing tmux sessions, and non-interactive shells
- Vi keybindings with mouse support enabled
- Custom keybindings: `|` for horizontal split, `-` for vertical split
- Vim-style pane navigation: `h/j/k/l`
- 24-hour clock, 10,000 line history

**Includes:**
- `tailscale.nix` - Tailscale VPN with firewall configuration
- `syncthing.nix` - File synchronization service
- `shell-aliases.nix` - Common command aliases

### Desktop Modules

#### desktop-minimal.nix
Minimal desktop configuration optimized for programmatic photo processing and AI workstations.

**Desktop Environment:**
- KDE Plasma 6
- SDDM display manager (Wayland)
- PipeWire audio

**Features:**
- Minimal application set focused on development workflows
- Python development environment for AI/ML and computer vision
- System libraries for photoAlbumOrganizer (face recognition, image processing)
- Essential KDE applications only
- OpenCV, dlib, OpenBLAS for computer vision tasks

**Includes:**
- `bitwarden.nix` - Secrets management
- `home-manager` - For starship and bash configuration

**Applications & Libraries:**
- Development: Python 3, VSCode FHS, Git, CMake, GCC
- Computer Vision: OpenCV, dlib, OpenBLAS, LAPACK
- Image Viewing: Gwenview (for verifying processing results)
- Essentials: Firefox, VLC, KDE utilities

**Optimized for:** [photoAlbumOrganizer](https://github.com/fkadriver/photoAlbumOrganizer) - programmatic photo organization with face recognition

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
- `3d-printing.nix` - Orca Slicer, PrusaSlicer, FreeCAD, Blender
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
- Used by: `prodesk`, `installer`
- Automatically applied during automated installation
- Can be customized per-host by overriding the `disko.devices.disk.main.device` option
- Other hosts (latitude, airbook) use manual filesystem configuration

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
- OpenSCAD, PrusaSlicer, FreeCAD, Blender, MeshLab

**Options:**
- `my.printing.enable` - Core 3D printing tools
- `my.printing.fonts.enable` - 3D-safe emboss fonts (enables `my.fonts.printing3d`)
- `my.printing.repairTools` - SVG/STL repair tools (Inkscape, Potrace, FontForge)
- `my.printing.generateTestArtifacts` - Font test plate/keychain generators

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
# For HP ProDesk desktop (minimal photo/AI workstation)
sudo nixos-rebuild switch --flake .#prodesk

# For Dell Latitude 7480 with KDE (default)
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
   - Select configuration (latitude-xfce, latitude-kde, airbook-kde, or prodesk)
   - Choose target disk
   - Confirm installation

The installer will automatically:
- Connect to WiFi (JEN_ACRES network pre-configured)
- Partition the disk using disko (1GB /boot + LVM with 8GB swap + root)
- Install NixOS directly from the git repository
- Offer to reboot

Note: The installer fetches the configuration directly from git, no cloning needed.

### Manual Installation with Disko

If you prefer manual installation using disko for automatic disk partitioning:

```bash
# 1. Partition the disk (using git flake directly from GitHub via HTTPS)
sudo nix run github:nix-community/disko -- \
  --mode disko \
  --flake github:fkadriver/nixos#latitude \
  --arg device '"/dev/sdX"'

# 2. Install NixOS (directly from GitHub, no cloning needed)
sudo nixos-install --flake github:fkadriver/nixos#latitude

# 3. Reboot
sudo reboot
```

Replace `latitude` with your configuration: `prodesk`, `latitude`, `airbook`, etc.

All configurations now support disko for automated disk partitioning!

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

### HP ProDesk

**Configuration:** Minimal desktop optimized for programmatic photo processing and AI.

**Key Features:**
- Lightweight KDE Plasma 6 desktop
- Python development environment with computer vision libraries
- System libraries for photoAlbumOrganizer (OpenCV, dlib, face_recognition)
- VSCode with FHS environment for AI frameworks
- CMake, GCC for compiling native Python extensions
- Automated disk partitioning with disko
- No automatic backups (Borg not configured)

**Automated Installation with Disko (Recommended):**

1. **Boot NixOS installer USB**

2. **Identify your target disk:**
   ```bash
   lsblk  # Find your disk (e.g., /dev/sda, /dev/nvme0n1)
   ```

3. **Run disko to partition and format automatically:**
   ```bash
   sudo nix run github:nix-community/disko -- \
     --mode disko \
     --flake github:fkadriver/nixos#prodesk \
     --arg device '"/dev/sda"'  # Replace with your disk
   ```
   This creates:
   - 1 GB EFI boot partition
   - LVM with 8 GB swap + remaining space for root

4. **Install NixOS directly from GitHub:**
   ```bash
   sudo nixos-install --flake github:fkadriver/nixos#prodesk
   ```

5. **Set root password when prompted**

6. **Reboot and login**

7. **After first boot, get AGE key for Bitwarden secrets:**
   ```bash
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```
   Add this key to `.sops.yaml` in your repository to enable secret management (including SSH keys)

**Note:** The ProDesk 600 G4 has Intel UHD Graphics 630 (integrated graphics) - hardware acceleration is already configured.

**Setting up photoAlbumOrganizer:**

After installation, you can set up your photo processing environment:
```bash
# Clone your photoAlbumOrganizer project
git clone https://github.com/fkadriver/photoAlbumOrganizer.git
cd photoAlbumOrganizer

# All system dependencies (CMake, OpenCV, dlib, etc.) are already installed!
# Just create a Python virtual environment and install Python packages
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# The environment includes:
# - CMake for compiling dlib
# - OpenCV for computer vision
# - OpenBLAS and LAPACK for linear algebra
# - dlib for face recognition
# - All necessary build tools
```

**AI/ML Setup:**

After installation, create Python virtual environments for your AI workloads:
```bash
python -m venv ~/ai-env
source ~/ai-env/bin/activate
pip install torch torchvision torchaudio  # or tensorflow, etc.
```

**Inspired by:** [mkellyxp/nixbook](https://github.com/mkellyxp/nixbook) - A project for converting old computers into lightweight NixOS workstations.

### MacBook Air 7,2

**WiFi:** Uses Broadcom BCM43xx chipset with broadcom-sta driver (wl module).

**Security Notice:** The broadcom-sta driver has known CVEs (CVE-2019-9501, CVE-2019-9502) and is marked as insecure. The configuration explicitly permits this package for hardware compatibility. Consider alternative WiFi hardware for better security.

**CPU:** Intel Core i5-5250U or i7-5650U (Broadwell architecture)

### Dell Latitude 7480

**Additional Features:**
- Logitech wireless peripheral support with GUI tools

### Dell Latitude E7270 (vm01)

**Purpose:** Immich photo management server

**Configuration:**
- **Service Tag:** 7NYTSF2
- **Service User:** `immich` (system user with bash shell for `su` access)
  - Home directory: `/opt/immich`
  - Member of `docker` group
- **External Storage:** 1TB Toshiba drive
  - Mount point: `/mnt/immich`
  - Mounted by UUID for reliability
  - Owned by `immich:immich`
- **Features:** Borg backup to nas01, wireless networking, docker

**Note:** Headless server - no desktop environment installed. Access via SSH or Tailscale.

## Directory Structure

```
.
├── flake.nix                      # Main flake configuration (auto-discovers modules)
├── hosts/
│   ├── prodesk/
│   │   ├── default.nix            # HP ProDesk desktop (minimal photo/AI workstation)
│   │   └── hardware.nix           # Hardware configuration (template)
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
│   ├── vm01/
│   │   ├── default.nix            # Dell Latitude E7270 (Immich server)
│   │   └── hardware-configuration.nix  # Hardware configuration
│   └── installer/
│       └── default.nix            # Automated installer ISO
├── modules/                       # Auto-discovered by flake.nix
│   ├── common.nix                 # Base configuration (server-safe)
│   ├── desktop-minimal.nix        # Minimal desktop for photo/AI workstations
│   ├── laptop-xfce.nix            # XFCE laptop configuration
│   ├── laptop-kde.nix             # KDE Plasma laptop configuration
│   ├── laptop-minimal.nix         # Minimal testing configuration
│   ├── 3d-printing.nix            # Orca Slicer, PrusaSlicer, FreeCAD, Blender
│   ├── borg-backup.nix            # Encrypted backup to remote servers
│   ├── bitwarden.nix              # Secrets management
│   ├── wireless.nix               # WiFi configuration
│   ├── disko-config.nix           # Automated disk partitioning
│   ├── font.nix                   # Font management (documents, craft, printing3d, nerd)
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

## Documentation

### Adding New Hosts

See [docs/adding-hosts.md](docs/adding-hosts.md) for a comprehensive guide on:
- Adding new physical machines to the repository
- Creating host configuration variants (e.g., KDE, XFCE, minimal)
- Hardware configuration setup
- Module selection and configuration
- Testing and deployment
- Best practices and troubleshooting

### Additional Guides

- [docs/borg-backup.md](docs/borg-backup.md) - Backup configuration and usage
- [docs/bitwarden.md](docs/bitwarden.md) - Secrets management with Bitwarden
- [docs/multi-monitor-setup.md](docs/multi-monitor-setup.md) - Multi-monitor profile configuration
- [docs/nixos-binary-compatibility.md](docs/nixos-binary-compatibility.md) - Running non-NixOS binaries

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

## Daily driver profiles (Latitude + Airbook)

This repo uses a shared `modules/daily-driver.nix` module for Scott's two daily-driver machines:

- **Latitude (KDE)**: multi-monitor, typically docked
- **Airbook (XFCE)**: lighter desktop for battery life

`daily-driver.nix` contains shared applications, fonts, and 3D-printing tooling; the desktop environment modules (`modules/laptop-kde.nix`, `modules/laptop-xfce.nix`) contain DE-specific settings only.

### Fonts

Fonts are managed by `modules/font.nix` with modular categories:

| Option | Description | Fonts |
|--------|-------------|-------|
| `documents` | Office/printing | DejaVu, Noto, Liberation, Source family, Inter |
| `craft` | Decorative/Cricut | Great Vibes, Allura, Parisienne, EB Garamond, Libre Baskerville |
| `printing3d` | 3D printing optimized | Roboto, Lato, Open Sans, Montserrat, Oswald, Archivo, Raleway, Orbitron |
| `nerd` | Terminal fonts | JetBrains Mono, Fira Code (with Nerd Font glyphs) |
| `viewer` | Font tools | font-manager, gnome-font-viewer, fontforge |

All categories are enabled in `modules/daily-driver.nix` for laptop-xfce and laptop-kde.

### 3D printing font test artifacts

When `my.printing.generateTestArtifacts = true;` is enabled (via `daily-driver.nix`), these commands are available:

- `generate-font-plate "Your text"` → outputs `~/.cache/font-test-plate/font_plate.stl`
- `generate-font-keychains "Your text"` → outputs multiple STLs under `~/.cache/font-keychains/`

### Helpful Nix aliases

System rebuild aliases are defined in `modules/shell-aliases.nix`, for example:

- `nos-rebuild` → `sudo nixos-rebuild switch --flake .`
- `nos-test` → `sudo nixos-rebuild test --flake .`
- `nos-boot` → `sudo nixos-rebuild boot --flake .`
