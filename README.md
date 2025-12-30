# NixOS Flake Configuration

A modular NixOS configuration for laptops with Hyprland, supporting multiple hardware configurations.

## Supported Hardware

- **latitude**: Dell Latitude 7480
- **airbook**: Apple MacBook Air 7,2 (13-inch, Early 2015/Mid 2017)

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

#### laptop.nix
Laptop-specific configuration module that serves as a shell for desktop modules.

**Features:**
- Development tools (VSCodium, Claude Code, Python)
- Gaming support (Heroic, Lutris, Wine)
- Media tools (Shotwell)
- Firefox browser
- nix-ld for running non-NixOS binaries
- JEN_ACRES WiFi auto-connection

**Includes:**
- `hyprland.nix` - Wayland compositor and desktop environment
- `bitwarden.nix` - Secrets management

#### hyprland.nix
Complete Hyprland Wayland desktop environment.

**Features:**
- Hyprland compositor with XWayland support
- Greetd with TUIgreet login manager
- Full Wayland environment setup
- PipeWire audio (with ALSA, PulseAudio, JACK support)
- XDG portals for screen sharing and file pickers
- GNOME Keyring for credential storage
- Qt and GTK theming (Adwaita Dark)

**Included Applications:**
- **Terminal**: Kitty
- **Status Bar**: Waybar
- **App Launcher**: Rofi
- **Notifications**: Dunst
- **Screenshots**: Grim + Slurp
- **Screen Recording**: wf-recorder
- **File Manager**: Thunar
- **Image Viewer**: imv
- **PDF Viewer**: Zathura
- **Hyprland Tools**: hyprpaper, hyprlock, hypridle, hyprpicker

**Fonts:**
- Noto Fonts (including CJK and Color Emoji)
- Font Awesome
- Nerd Fonts (JetBrains Mono, Fira Code)

#### shell-aliases.nix
System-wide shell aliases for common commands.

**Aliases:**
- `nas01` - SSH to nas01 via Tailscale
- `slap` - SSH to latitude via Tailscale
- `log01` - SSH to sands-log01 via Tailscale
- `gpc` - Grep with color output

#### bitwarden.nix
Secrets management module (currently includes Bitwarden CLI).

Future integration points for:
- Syncthing device IDs and folder configurations
- Tailscale auth keys
- WiFi passwords
- SSH keys

Can be extended with sops-nix or agenix for encrypted secrets management.

#### idrive-e360.nix
Enterprise cloud backup service integration for offsite backups.

**Features:**
- iDrive e360 thin client for Linux
- Systemd service for background backup daemon
- Optional scheduled automatic backups via systemd timers
- Security hardening (PrivateTmp, restricted filesystem access)

**Configuration Options:**
- Custom backup schedules (daily, weekly, custom times)
- User-specific backup settings
- Config and data directory customization

**Usage:**
Requires downloading the .deb package from your iDrive e360 console.
See "iDrive e360 Cloud Backup" section below for setup instructions.

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
# For Dell Latitude 7480
sudo nixos-rebuild switch --flake .#latitude

# For MacBook Air 7,2
sudo nixos-rebuild switch --flake .#airbook
```

### Build Installation ISO (MacBook Air only)

The MacBook Air configuration includes support for building a NixOS installation ISO:

```bash
nix build .#nixosConfigurations.airbook.config.system.build.isoImage
```

The ISO will be in `result/iso/`. To write to a USB drive:

```bash
sudo dd if=result/iso/nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

**Important:** Replace `/dev/sdX` with your actual USB drive device.

### Test Configuration in VM

Before installing on hardware, you can test configurations in a virtual machine:

```bash
# Build and run VM for Dell Latitude 7480
nix build .#nixosConfigurations.latitude.config.system.build.vm
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

**Testing the Hyprland Environment:**
- The VM will boot to the Greetd login screen
- Select Hyprland and log in to test the desktop environment
- Useful for validating configuration changes before deployment

### Check Configuration

```bash
nix flake check
```

## Installation Guide (MacBook Air)

After booting from the ISO USB drive:

### 1. Connect to WiFi
```bash
sudo systemctl start NetworkManager
nmtui  # Connect to JEN_ACRES
```

### 2. Partition the Disk
```bash
# Check disk name (likely /dev/sda)
lsblk

# Create GPT partition table and partitions
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart primary 512MiB 100%
```

### 3. Format Partitions
```bash
sudo mkfs.fat -F 32 -n boot /dev/sda1
sudo mkfs.ext4 -L nixos /dev/sda2
```

### 4. Mount Filesystems
```bash
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot
```

### 5. Install Configuration
```bash
# Generate hardware config (for reference)
sudo nixos-generate-config --root /mnt

# Clone your NixOS configuration
nix-shell -p git
cd /mnt/etc/nixos
sudo mv configuration.nix configuration.nix.backup
sudo git clone https://github.com/fkadriver/nixos.git .
```

### 6. Enable Bootloader
```bash
# Edit the hardware configuration
sudo nano /mnt/etc/nixos/hosts/airbook-hardware.nix

# Uncomment these two lines (around line 19-20):
# boot.loader.systemd-boot.enable = true;
# boot.loader.efi.canTouchEfiVariables = true;
```

### 7. Install NixOS
```bash
sudo nixos-install --flake /mnt/etc/nixos#airbook
```

### 8. Reboot
```bash
# Set root password when prompted, then:
sudo reboot
```

After reboot, remove the USB drive and boot into your new NixOS installation!

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
├── flake.nix                      # Main flake configuration
├── hosts/
│   ├── latitude.nix         # Dell Latitude 7480 configuration
│   ├── latitude-hardware.nix
│   ├── airbook.nix          # MacBook Air 7,2 configuration
│   └── airbook-hardware.nix
├── modules/
│   ├── common.nix                 # Base configuration (server-safe)
│   ├── laptop.nix                 # Laptop-specific configuration
│   ├── hyprland.nix               # Hyprland desktop environment
│   ├── hyprland-config.nix        # Default Hyprland keybindings
│   ├── bitwarden.nix              # Secrets management
│   ├── idrive-e360.nix            # Cloud backup service
│   ├── shell-aliases.nix          # System-wide aliases
│   ├── syncthing.nix              # File synchronization
│   ├── tailscale.nix              # VPN configuration
│   └── user-scott.nix             # User account
└── pkgs/
    └── idrive-e360/
        └── default.nix            # iDrive e360 package definition
```

## Hyprland Usage

### First Login

After installation, you'll be greeted by TUIgreet. Select "Hyprland" and log in with your user credentials.

### Key Applications

- **Super + Enter** - Launch terminal (Kitty) - *Note: Configure in Hyprland config*
- **Super + D** - Application launcher (Rofi) - *Note: Configure in Hyprland config*
- **Screenshots** - Use `grim` and `slurp` commands
- **File Manager** - Run `thunar` from terminal or launcher
- **Network Manager** - Access via `nm-applet` in system tray
- **Audio Control** - Use `pavucontrol` for audio settings

### Customization

Hyprland configuration is managed declaratively through NixOS. To customize:

1. Create a Hyprland configuration file in your home directory or add home-manager
2. Configure keybindings, monitors, workspaces, etc.
3. Reference the example configurations:
   - [Fortydeux-NixOS-System-Flake](https://github.com/WhatstheUse/Fortydeux-NixOS-System-Flake)
   - [hyprvibe](https://github.com/ChrisLAS/hyprvibe)

## Network Configuration

### WiFi

The JEN_ACRES WiFi network is configured to auto-connect in `laptop.nix`. To add additional networks:

1. Use NetworkManager's `nmtui` or `nmcli` tools
2. Or add additional profiles to `laptop.nix` following the JEN_ACRES pattern

### Tailscale

Tailscale is enabled by default. After first boot:

```bash
sudo tailscale up
```

Then authenticate via the provided URL.

## iDrive e360 Cloud Backup

iDrive e360 provides enterprise-grade offsite backup for your laptops and servers. The configuration includes a custom NixOS module for seamless integration.

### Initial Setup

1. **Download the iDrive e360 Client**

   Log into your iDrive e360 account at [https://www.idrive.com/endpoint-backup/](https://www.idrive.com/endpoint-backup/):
   - Click "Add Devices"
   - Select the "Linux" tab
   - Download the `.deb` package for Ubuntu/Debian
   - Save it to a known location (e.g., `/home/scott/Downloads/idrive360.deb`)

2. **Enable iDrive e360 in Your Configuration**

   Add the iDrive e360 module to your host configuration. For example, in `hosts/latitude.nix`:

   ```nix
   imports = [
     ./latitude-hardware.nix
     inputs.self.modules.common
     inputs.self.modules.laptop
     inputs.self.modules.user-scott
     inputs.self.modules.idrive-e360  # Add this line
   ];
   ```

3. **Configure iDrive e360**

   Add configuration options to your host file:

   ```nix
   config = {
     networking = {
       hostName = "latitude-nixos";
     };

     # iDrive e360 configuration
     services.idrive-e360 = {
       enable = true;
       debFile = /home/scott/Downloads/idrive360.deb;  # Path to downloaded .deb
       user = "scott";

       # Optional: Enable scheduled backups
       scheduledBackup = {
         enable = true;
         schedule = "daily";  # Options: "daily", "weekly", "hourly", "Mon 09:00", etc.
       };
     };

     system = {
       stateVersion = "25.04";
     };
   };
   ```

4. **Rebuild Your System**

   ```bash
   sudo nixos-rebuild switch --flake .#latitude
   ```

5. **Configure Backup Settings**

   After the system rebuild, the iDrive e360 client will be available. Run the initial configuration:

   ```bash
   # The binary name may vary - check available commands:
   which idrive360

   # Run the client to configure your backup settings
   idrive360
   ```

   Follow the prompts to:
   - Authenticate with your iDrive e360 account
   - Select folders to backup
   - Configure backup schedule (if not using systemd timers)
   - Set retention policies

### Managing Backups

**Check Service Status:**
```bash
systemctl status idrive-e360
```

**View Backup Logs:**
```bash
journalctl -u idrive-e360 -f
```

**Manual Backup:**
```bash
# Trigger an immediate backup
systemctl start idrive-e360-backup
```

**Check Timer Status (if scheduled backups enabled):**
```bash
systemctl list-timers idrive-e360-backup
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | false | Enable iDrive e360 service |
| `debFile` | path | null | Path to downloaded .deb file |
| `user` | string | "scott" | User account for backups |
| `configDir` | string | "/home/user/.idrive360" | Config directory |
| `dataDir` | string | "/home/user" | Root directory to backup |
| `autoStart` | boolean | true | Auto-start service on boot |
| `scheduledBackup.enable` | boolean | false | Enable scheduled backups |
| `scheduledBackup.schedule` | string | "daily" | Backup schedule (systemd timer format) |

### Security Notes

- The iDrive e360 service runs with restricted permissions
- Configuration directory has 700 permissions (user-only access)
- Service uses `PrivateTmp` and `ProtectSystem=strict` for isolation
- Only specified directories have read/write access

### Troubleshooting

**Service Won't Start:**
```bash
# Check for errors
journalctl -u idrive-e360 --since "1 hour ago"

# Verify the binary exists
ls -la /nix/store/*/bin/idrive360
```

**Permission Issues:**
```bash
# Ensure config directory exists with correct permissions
ls -la ~/.idrive360
```

**Package Build Failures:**

If the initial build fails, you may need to adjust the package definition in `pkgs/idrive-e360/default.nix` based on the actual structure of the .deb file. Inspect your .deb:

```bash
dpkg-deb -c /path/to/idrive360.deb
```

## Future Enhancements

- **Home Manager Integration**: For user-specific configuration management
- **Secrets Management**: Integrate sops-nix or agenix with bitwarden.nix
- **Hyprland Dotfiles**: Declarative Hyprland configuration via home-manager
- **Server Configurations**: Create server-specific configurations using common.nix as base
- **Additional Hardware**: Add support for more hardware configurations

## Contributing

This is a personal NixOS configuration. Feel free to use it as inspiration for your own setup.

## License

This configuration is provided as-is for personal use.

## Acknowledgments

- Inspired by [Fortydeux-NixOS-System-Flake](https://github.com/WhatstheUse/Fortydeux-NixOS-System-Flake)
- Inspired by [hyprvibe](https://github.com/ChrisLAS/hyprvibe)
- Based on https://mynixos.com/fkadriver/Driver
