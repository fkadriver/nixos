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
./result/bin/run-latitude-vm

# Build and run VM for MacBook Air 7,2
nix build .#nixosConfigurations.airbook.config.system.build.vm
./result/bin/run-airbook-vm
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
└── modules/
    ├── common.nix                 # Base configuration (server-safe)
    ├── laptop.nix                 # Laptop-specific configuration
    ├── hyprland.nix               # Hyprland desktop environment
    ├── bitwarden.nix              # Secrets management
    ├── shell-aliases.nix          # System-wide aliases
    ├── syncthing.nix              # File synchronization
    ├── tailscale.nix              # VPN configuration
    └── user-scott.nix             # User account
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
