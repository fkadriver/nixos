# Adding New Hosts and Host Configurations

This guide explains how to add new hosts or host configurations to this NixOS flake repository.

## Understanding the Structure

### Hosts vs Host Configurations

- **Host Configuration**: A variant of a host with a different desktop environment or module set (e.g., `latitude-kde`, `latitude-xfce`, `latitude-minimal`)

### Directory Layout

```
hosts/
├── latitude/
│   ├── default.nix       # Main configuration (imports laptop-kde)
│   ├── kde.nix          # KDE variant configuration
│   ├── xfce.nix         # XFCE variant configuration
│   ├── minimal.nix      # Minimal testing configuration
│   ├── hardware.nix     # Hardware-specific settings
│   └── syncthing.nix    # Host-specific syncthing config
│   ├── default.nix
│   └── hardware.nix
└── airbook/
    ├── default.nix
    ├── kde.nix
    └── hardware.nix
```

## Adding a New Host

Follow these steps to add a completely new machine to the repository.

### 1. Generate Hardware Configuration

On the target machine, run:

```bash
sudo nixos-generate-config --show-hardware-config > /tmp/hardware.nix
```

### 2. Create Host Directory

```bash
mkdir -p hosts/newhostname
```

### 3. Create `hardware.nix`

Copy the generated hardware configuration:

```bash
cp /tmp/hardware.nix hosts/newhostname/hardware.nix
```

Review and adjust:
- File system mounts
- Boot loader settings
- Hardware-specific kernel modules
- Graphics drivers

### 4. Create `default.nix`

Create `hosts/newhostname/default.nix` based on this template:

```nix
{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      # Add desktop module based on your needs:
      # inputs.self.nixosModules.desktop-minimal
      # inputs.self.nixosModules.laptop-kde
      # inputs.self.nixosModules.laptop-xfce
      inputs.self.nixosModules.user-scott
      # Add optional modules:
      # inputs.self.nixosModules.logitech
      # inputs.self.nixosModules.multi-monitor
      # inputs.self.nixosModules.virtualbox
    ];

    config = {
      networking = {
        hostName = "newhostname";
      };

      # Optional: Enable Borg backup
      # services.borg-backup = {
      #   enable = true;
      #   repository = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/repos/newhostname";
      #   encryption.passphraseFile = "/etc/borg-passphrase";
      #   sshKeyFile = "/home/scott/.ssh/id_ed25519";
      # };

      system = {
        stateVersion = "25.11";
        nixos.label = "newhostname";  # Optional: custom boot menu label
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";  # or "aarch64-linux" for ARM
}
```

### 5. Add to `flake.nix`

Edit the root `flake.nix` and add your host to the `nixosConfigurations` section:

```nix
nixosConfigurations = {
  # ... existing configurations ...
  newhostname = import ./hosts/newhostname flakeContext;
};
```

### 6. Test the Configuration

Build the configuration without installing:

```bash
nix build .#nixosConfigurations.newhostname.config.system.build.toplevel
```

Check for errors:

```bash
nix flake check
```

### 7. Deploy

#### Option A: Local Installation

If you're on the target machine:

```bash
sudo nixos-rebuild switch --flake .#newhostname
```

#### Option B: Remote Installation

From another machine with access:

```bash
nixos-rebuild switch --flake .#newhostname \
  --target-host scott@newhostname \
  --use-remote-sudo
```

#### Option C: Fresh Installation via Installer ISO

Build and write the installer, then boot the target machine from USB:

```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
sudo ./scripts/prepare-installer-usb.sh result/iso/nixos-*.iso /dev/sdX
```

The installer has SSH enabled with root login. Once the machine is on the network:

```bash
ssh root@<ip-address>   # password: nixos
/etc/nixos-install-helper.sh
```

The install helper will partition the disk with disko, then pull and install the flake from GitHub. After it completes, reboot into the new system.

## Adding a New Host Configuration (Variant)

To add a variant configuration for an existing host (e.g., add a KDE variant to a laptop that has XFCE):

### 1. Create the Variant Configuration File

Create `hosts/hostname/kde.nix` (or whatever variant name you want):

```nix
{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde  # Different desktop module
      inputs.self.nixosModules.user-scott
      # Import any host-specific config files if needed
      # ./syncthing.nix
    ];

    config = {
      networking = {
        hostName = "hostname";  # Same hostname as default.nix
      };

      # Host-specific configuration
      # services.borg-backup = { ... };

      system = {
        stateVersion = "25.11";
        # The boot label will be inherited from laptop-kde module ("KDE")
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
```

### 2. Add to `flake.nix`

Add the variant to `nixosConfigurations`:

```nix
nixosConfigurations = {
  hostname = import ./hosts/hostname flakeContext;           # default
  hostname-kde = import ./hosts/hostname/kde.nix flakeContext;  # variant
};
```

### 3. Test and Deploy

Test the variant:

```bash
nix build .#nixosConfigurations.hostname-kde.config.system.build.toplevel
```

Switch to the variant:

```bash
sudo nixos-rebuild switch --flake .#hostname-kde
```

## Common Modules to Import

### Essential Modules
- `common.nix` - Required for all configurations (CLI tools, Docker, Tailscale)
- `user-scott.nix` - User account and shell configuration

### Desktop Modules (choose one)
- `desktop-minimal.nix` - Minimal KDE for photo/AI workstations
- `laptop-kde.nix` - Full-featured KDE Plasma 6 desktop
- `laptop-xfce.nix` - Full-featured XFCE desktop

### Optional Feature Modules
- `logitech.nix` - Logitech device support (Solaar, numlock)
- `multi-monitor.nix` - Multi-monitor autorandr profiles
- `virtualbox.nix` - VirtualBox support
- `wireless.nix` - WiFi configuration (for laptops without NetworkManager)
- `3d-printing.nix` - 3D printing tools (Orca Slicer, PrusaSlicer, FreeCAD)
- `printing.nix` - Printer support (CUPS)
- `vscode.nix` - VSCode with gnome-keyring
- `borg-backup.nix` - Borg backup module (enable via services.borg-backup)

### Secret Management
- `bitwarden.nix` + `bitwarden-scott.nix` - Automatically included in desktop modules

## Boot Menu Labels

Boot menu labels help identify different configurations in the GRUB/systemd-boot menu:

```nix
system.nixos.label = "hostname-description";
```

If a module (like `laptop-kde.nix` or `desktop-minimal.nix`) already sets a label, you can override it by setting it explicitly in your host configuration. The module labels use `lib.mkDefault`, allowing host-specific overrides to take precedence.

## Hardware Configuration Tips

### Graphics Drivers

For NVIDIA GPUs, uncomment in your host's `default.nix`:

```nix
hardware.opengl = {
  enable = true;
  driSupport = true;
  driSupport32Bit = true;
};
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  open = false;  # Use proprietary driver
  nvidiaSettings = true;
  package = config.boot.kernelPackages.nvidiaPackages.stable;
};
```

### Disk Configuration with Disko

For automated installation with disk partitioning, add disko support:

```nix
imports = [
  ./hardware.nix
  inputs.disko.nixosModules.disko
  inputs.self.nixosModules.disko-config
  # ... other imports
];
```


## Bitwarden Secrets Setup

If your host uses the bitwarden module (included in `desktop-minimal` and laptop modules):

1. After first boot, the AGE key is automatically generated at `/var/lib/sops-nix/key.txt`

2. Get the public key to add to `.sops.yaml`. For headless hosts (no local console
   access), retrieve it via SSH from your management machine:
   ```bash
   ssh scott@<hostname> 'sudo age-keygen -y /var/lib/sops-nix/key.txt'
   ```
   Or locally on the new host:
   ```bash
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```
   Either way outputs: `age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

3. Add the public key to `.sops.yaml` in the repository:
   ```yaml
   keys:
     - &admin age1xxxxxxxxxxxxxx        # Your existing key
     - &newhost age1yyyyyyyyyyyyyy      # New host's key

   creation_rules:
     - path_regex: secrets/secrets\.yaml$
       key_groups:
         - age:
             - *admin
             - *newhost
   ```

4. **Re-encrypt secrets with all keys** (critical step!):
   ```bash
   sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops updatekeys secrets/secrets.yaml
   ```
   This decrypts the file with your current key and re-encrypts it for all keys listed in `.sops.yaml`.

   **Note**: You must specify `SOPS_AGE_KEY_FILE` because NixOS stores the key at `/var/lib/sops-nix/key.txt`, not in sops' default locations.

5. Commit and rebuild:
   ```bash
   git add .sops.yaml secrets/secrets.yaml
   git commit -m "Add AGE key for newhost"
   git push

   # On the new host — clone the repo first, then rebuild
   git clone https://github.com/fkadriver/nixos ~/git/nixos
   cd ~/git/nixos
   sudo nixos-rebuild switch --flake .#newhost
   ```

**Important**: The `sops updatekeys` command is required - the secrets won't work on the new host until the file is re-encrypted with its key!

See [docs/bitwarden.md](bitwarden.md) for detailed setup instructions.

## Testing Your Configuration

Before deploying to production, run these checks:

```bash
# Check flake syntax and build all configurations
nix flake check

# Build specific configuration
nix build .#nixosConfigurations.hostname.config.system.build.toplevel

# Dry build (don't create result symlink)
nixos-rebuild dry-build --flake .#hostname

# Test in a VM
nixos-rebuild build-vm --flake .#hostname
./result/bin/run-*-vm
```

## Troubleshooting

### Conflicting Option Values

If you see errors like:
```
error: The option `system.nixos.label' has conflicting definition values
```

This means multiple modules are setting the same option with the same priority. Solutions:
1. Use `lib.mkDefault` in the module that should be overridable
2. Use `lib.mkForce` in the configuration that should override
3. Remove the duplicate option from one location

### Missing Hardware Support

If hardware isn't working:
1. Check `hardware.nix` for missing kernel modules
2. Review `nixos-hardware` flake for device-specific modules
3. Add required firmware packages to `hardware.enableRedistributableFirmware`

### Build Failures

Common causes:
1. Missing flake inputs - add to `flake.nix` inputs section
2. Syntax errors - check with `nix flake check`
3. Missing system packages - add to appropriate module's `environment.systemPackages`

## Example: Adding a New Laptop

Let's walk through adding a ThinkPad T480:

```bash
# 1. Create directory
mkdir -p hosts/thinkpad

# 2. Generate hardware config (on the ThinkPad)
sudo nixos-generate-config --show-hardware-config > /tmp/hardware.nix
# Copy to hosts/thinkpad/hardware.nix

# 3. Create default.nix
cat > hosts/thinkpad/default.nix << 'EOF'
{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.printing
    ];

    config = {
      networking.hostName = "thinkpad";
      system = {
        stateVersion = "25.11";
        nixos.label = "thinkpad";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [ nixosModule ];
  system = "x86_64-linux";
}
EOF

# 4. Add to flake.nix
# Edit flake.nix and add: thinkpad = import ./hosts/thinkpad flakeContext;

# 5. Test
nix flake check
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel

# 6. Deploy
sudo nixos-rebuild switch --flake .#thinkpad
```

## Best Practices

1. **Keep hardware.nix clean** - Only hardware-specific settings
2. **Use modules** - Don't duplicate configuration across hosts
3. **Test before committing** - Run `nix flake check`
4. **Document host-specific quirks** - Add comments in the host's default.nix
5. **Use consistent naming** - hostname, hostname-variant (e.g., latitude, latitude-kde)
6. **Set appropriate boot labels** - Makes it easy to identify configurations in boot menu
7. **Version control** - Commit working configurations before experimenting

## Additional Resources

- [NixOS Manual - Configuration Syntax](https://nixos.org/manual/nixos/stable/index.html#sec-configuration-syntax)
- [NixOS Hardware Modules](https://github.com/NixOS/nixos-hardware)
- [Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- Repository docs:
  - [docs/bitwarden.md](bitwarden.md) - Secrets management setup
  - [docs/borg-backup.md](borg-backup.md) - Backup configuration
  - [docs/multi-monitor-setup.md](multi-monitor-setup.md) - Multi-monitor profiles
