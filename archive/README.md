# Archived Configurations

This folder contains NixOS modules and configurations that are no longer actively used but are kept for reference or future use.

## Contents

### modules/

#### hyprland.nix & hyprland-config.nix
Hyprland Wayland compositor configuration. Archived because:
- Works when launched from TTY but had issues with LightDM integration
- May revisit when Hyprland desktop manager support improves

#### laptop-hyprland.nix
Laptop profile for Hyprland desktop environment.

#### idrive-e360.nix
iDrive e360 enterprise backup service module. Archived because:
- Bundled Python 3.5 binary has a bug: "Get() takes no keyword arguments"
- This is an upstream issue in iDrive's proprietary binary
- Replaced with Borg backup to local NAS

### hosts/latitude/

#### hyprland.nix
Latitude host configuration for Hyprland desktop. Archived along with the Hyprland modules.

### pkgs/idrive-e360/

#### Dockerfile & docker-compose.yml
Docker containerization attempt for iDrive e360. Even in a container, the same Python bug occurs.

#### default.nix
Nix package definition for iDrive e360. Kept for reference if iDrive fixes their binary.

#### IDrive360.deb
The original .deb package from iDrive.

## Restoring Archived Configurations

To restore any of these configurations:

1. Move the module back to the appropriate directory (`modules/` or `hosts/`)
2. The flake's auto-discovery will automatically pick up modules in `modules/`
3. For host configurations, add an entry to `flake.nix` under `nixosConfigurations`

## Notes

- These configurations may require updates to work with current nixpkgs
- Some may have unresolved issues (documented above)
- Test thoroughly before deploying to production systems
