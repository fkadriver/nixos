# Multi-Monitor Setup Guide for NixOS XFCE

This guide explains how to configure your NixOS XFCE system for multi-monitor setups, particularly for laptops with docking stations.

## Overview

The multi-monitor configuration consists of:
- **autorandr**: Automatic display profile switching when monitors connect/disconnect
- **arandr**: GUI tool for configuring display layouts
- **XFCE panels**: Multiple panels so each monitor has its own application menu
- **Power management**: Proper lid switch behavior when docked

## Initial Setup

### 1. Rebuild Your System

First, rebuild your system to get the new configuration:

```bash
sudo nixos-rebuild switch --flake .#latitude-xfce
```

### 2. Configure Your Display Profiles

After rebuilding, you need to create autorandr profiles for your specific monitors.

#### Step 1: Get Monitor Information

Connect your monitors and run:

```bash
xrandr --query
```

This shows your monitor names (e.g., `eDP-1`, `DP-1`, `DP-2`, `HDMI-1`).

#### Step 2: Get Monitor Fingerprints

Run this command to get unique identifiers for each monitor:

```bash
autorandr --fingerprint
```

You'll see output like:
```
eDP-1 00ffffffffffff004d10...
DP-1 00ffffffffffff0010ac...
DP-2 00ffffffffffff0010ac...
```

#### Step 3: Configure Your First Profile Manually

1. Use the XFCE Display Settings or `arandr` GUI to arrange your monitors:
   ```bash
   arandr
   ```

2. Arrange monitors visually (drag and drop)
3. Click "Apply"
4. Save the profile:
   ```bash
   autorandr --save docked
   ```

#### Step 4: Create Mobile Profile

1. Disconnect all external monitors
2. Configure for laptop screen only using XFCE Display Settings or arandr
3. Save:
   ```bash
   autorandr --save mobile
   ```

#### Step 5: Update NixOS Configuration

Edit `/home/user/nixos/modules/autorandr-profiles.nix` and replace the placeholder fingerprints with your actual values from Step 2.

Example:
```nix
"docked" = {
  fingerprint = {
    eDP-1 = "00ffffffffffff004d10...";  # Your laptop fingerprint
    DP-1 = "00ffffffffffff0010ac...";   # Your first external monitor
    DP-2 = "00ffffffffffff0010ac...";   # Your second external monitor
  };
  config = {
    "eDP-1" = {
      enable = true;
      position = "0x0";
      mode = "1920x1080";  # Your laptop's resolution
      rate = "60.00";
    };
    "DP-1" = {
      enable = true;
      primary = true;
      position = "1920x0";
      mode = "1920x1080";  # Your external monitor resolution
      rate = "60.00";
    };
    "DP-2" = {
      enable = true;
      position = "3840x0";
      mode = "1920x1080";
      rate = "60.00";
    };
  };
};
```

#### Step 6: Rebuild Again

```bash
sudo nixos-rebuild switch --flake .#latitude-xfce
```

### 3. Test Automatic Switching

Now when you connect/disconnect monitors, autorandr should automatically switch profiles:

```bash
# Manually test profile switching
autorandr --change

# List available profiles
autorandr --list

# Switch to a specific profile
autorandr --load docked
```

## Setting Up Panels on Multiple Monitors

To have application menus accessible on each monitor (answering your question about menus following the mouse):

### The Solution: Multiple Panels

XFCE panels don't automatically follow the mouse, but you can create **separate panels on each monitor**.

### Steps:

1. **Right-click on the panel** → Select "Panel" → "Panel Preferences"

2. **Create a new panel** for each additional monitor:
   - Click the "+" button to create a new panel
   - In the "Display" tab, select the specific monitor output (e.g., DP-1, DP-2)
   - Under "Output", choose the specific monitor instead of "Automatic"

3. **Configure each panel**:
   - Add the "Applications Menu" or "Whisker Menu" plugin to each panel
   - Add other widgets you want (clock, system tray, etc.)
   - You can make panels identical or customize them differently

4. **Panel Layout Options**:
   - **Top panels on each monitor**: Traditional layout
   - **Bottom panels**: macOS-style
   - **Vertical panels**: Save vertical space
   - **Auto-hide**: Maximize screen space

### Recommended Setup for 3 Monitors:

1. **Panel 1** (Laptop screen - eDP-1):
   - Full panel with all plugins
   - Applications Menu, System Tray, Clock, etc.

2. **Panel 2** (External monitor 1 - DP-1):
   - Mirror of Panel 1, or simplified version
   - At minimum: Applications Menu + Clock

3. **Panel 3** (External monitor 2 - DP-2):
   - Same as Panel 2

This way, you can access the application menu on whichever monitor you're working on without moving the mouse across screens.

## XFCE Plugins Included

Your system now includes these useful XFCE plugins:

### Panel Plugins:
- **Battery Plugin**: Battery status (for laptops)
- **Clipman**: Clipboard manager
- **CPU Graph**: CPU usage visualization
- **Network Load**: Network traffic monitor
- **PulseAudio Plugin**: Volume control
- **System Load**: System resource monitor
- **Weather Plugin**: Weather information
- **Whisker Menu**: Modern application menu
- **XKB Plugin**: Keyboard layout switcher

### Applications:
- **arandr**: GUI display configuration
- **autorandr**: Automatic profile switching
- **Screenshooter**: Screenshot utility
- **Task Manager**: Process monitor
- **Ristretto**: Image viewer
- **Mousepad**: Text editor

### Thunar File Manager Plugins:
- Archive plugin (extract/create archives)
- Volume manager (automatic mounting)
- Media tags (view/edit media metadata)

## Power Management

### Lid Switch Behavior

The configuration includes smart lid switch handling:

- **When docked** (external monitors connected): Closing the lid does nothing (keeps system running)
- **When undocked**: Closing the lid suspends the system (configurable)
- **On external power**: Lid switch is ignored by default

You can adjust this in `/home/user/nixos/modules/multi-monitor.nix`:

```nix
services.logind = {
  lidSwitchDocked = "ignore";     # ignore, suspend, poweroff, hibernate
  lidSwitch = "suspend";          # When undocked
  lidSwitchExternalPower = "ignore";
};
```

### TLP Power Management

TLP is configured to:
- Disable USB auto-suspend (prevents docking station issues)
- Keep USB devices active when docked
- Optimize battery life when mobile

## Troubleshooting

### Monitors Not Detected

1. Check available outputs:
   ```bash
   xrandr --query
   ```

2. Force detection:
   ```bash
   autorandr --change --force
   ```

3. Check logs:
   ```bash
   journalctl -u autorandr.service
   ```

### Profile Not Switching Automatically

1. Verify udev rules are loaded:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

2. Manually trigger autorandr:
   ```bash
   autorandr --change --debug
   ```

### Panel Not Appearing on Monitor

1. Open Panel Preferences
2. Make sure "Output" is set to the correct monitor
3. Restart XFCE panel:
   ```bash
   xfce4-panel -r
   ```

### Reset Display Configuration

If things get messed up:
```bash
# Remove autorandr configs
rm -rf ~/.config/autorandr/

# Reset XFCE display settings
rm ~/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml

# Restart XFCE
xfce4-session-logout --reboot
```

## Advanced Configurations

### Different Wallpapers Per Monitor

XFCE 4.18+ supports per-monitor wallpapers:
1. Right-click desktop → Desktop Settings
2. In "Folder" tab, select your wallpaper
3. Click the monitor icon to set wallpaper for specific monitor

### Workspace Spanning

Configure workspaces to span all monitors or be per-monitor:
1. Settings → Workspaces
2. Adjust "Number of workspaces"
3. Check/uncheck "Use all monitors for workspaces"

### Screen Rotation

Some docking setups use portrait monitors. Configure in autorandr:
```nix
"DP-1" = {
  enable = true;
  rotate = "left";  # or "right", "inverted", "normal"
  mode = "1920x1080";
};
```

## Additional Resources

- [XFCE Panel Documentation](https://docs.xfce.org/xfce/xfce4-panel/preferences)
- [Autorandr GitHub](https://github.com/phillipberndt/autorandr)
- [Arandr Documentation](https://christian.amsuess.com/tools/arandr/)

## Quick Reference

```bash
# List monitor outputs
xrandr --query

# Get monitor fingerprints
autorandr --fingerprint

# Save current display config
autorandr --save profile-name

# Load a profile
autorandr --load profile-name

# Auto-detect and load matching profile
autorandr --change

# List saved profiles
autorandr --list

# Configure displays with GUI
arandr

# Restart XFCE panel
xfce4-panel -r
```
