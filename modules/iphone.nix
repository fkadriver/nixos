{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # iPhone integration for Linux
    # Allows photo sync, file transfer, and device management

    # Core iPhone/iOS support packages
    environment.systemPackages = with pkgs; [
      # libimobiledevice - Core library for communicating with iOS devices
      libimobiledevice        # Command-line tools (ideviceinfo, idevicepair, etc.)

      # File system mounting
      ifuse                   # Mount iPhone filesystem via FUSE

      # iOS app management
      ideviceinstaller        # Install/uninstall apps on iOS

      # Additional utilities
      libplist                # Work with iOS property lists
      # Note: idevicebackup2 is included in libimobiledevice
    ];

    # Enable usbmuxd service - required for iPhone communication
    # This service multiplexes connections to iOS devices over USB
    services.usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd;
    };

    # Enable avahi for network device discovery (AirDrop-like features)
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };

    # Add user to plugdev group for device access
    # Your user needs to be in this group to access iOS devices
    users.groups.plugdev = {};

    # Create a helper script for mounting iPhone
    environment.etc."mount-iphone.sh" = {
      text = ''
        #!/usr/bin/env bash
        # Helper script to mount iPhone

        echo "=== iPhone Mount Helper ==="
        echo ""
        echo "1. Connect your iPhone via USB"
        echo "2. Unlock your iPhone and tap 'Trust' if prompted"
        echo "3. This script will mount your iPhone to ~/iPhone"
        echo ""

        # Create mount point if it doesn't exist
        MOUNT_POINT="$HOME/iPhone"
        mkdir -p "$MOUNT_POINT"

        # Pair the device (required first time)
        echo "Pairing device..."
        idevicepair pair

        if [ $? -eq 0 ]; then
          echo "Device paired successfully!"
        else
          echo "Pairing failed. Make sure you unlocked your iPhone and tapped 'Trust'."
          exit 1
        fi

        # Mount the device
        echo "Mounting iPhone to $MOUNT_POINT..."
        ifuse "$MOUNT_POINT"

        if [ $? -eq 0 ]; then
          echo ""
          echo "✓ iPhone mounted successfully!"
          echo "  Location: $MOUNT_POINT"
          echo ""
          echo "Photos are usually in: $MOUNT_POINT/DCIM/"
          echo ""
          echo "To unmount, run: fusermount -u $MOUNT_POINT"
        else
          echo "Failed to mount iPhone. Make sure:"
          echo "  1. iPhone is unlocked"
          echo "  2. You tapped 'Trust' on the iPhone"
          echo "  3. usbmuxd service is running: systemctl status usbmuxd"
        fi
      '';
      mode = "0755";
    };

    # Create unmount helper
    environment.etc."unmount-iphone.sh" = {
      text = ''
        #!/usr/bin/env bash
        # Helper script to unmount iPhone

        MOUNT_POINT="$HOME/iPhone"

        if mountpoint -q "$MOUNT_POINT"; then
          fusermount -u "$MOUNT_POINT"
          echo "✓ iPhone unmounted from $MOUNT_POINT"
        else
          echo "iPhone is not mounted at $MOUNT_POINT"
        fi
      '';
      mode = "0755";
    };

    # Usage instructions in a README
    environment.etc."iphone-integration-readme.txt" = {
      text = ''
        ══════════════════════════════════════════════════════════════
                        iPhone Integration on NixOS
        ══════════════════════════════════════════════════════════════

        📱 FEATURES:
        ────────────────────────────────────────────────────────────
        ✓ View and transfer photos from iPhone
        ✓ Mount iPhone filesystem (like a USB drive)
        ✓ Backup and restore iPhone
        ✓ Manage apps (install/uninstall)
        ✓ Access device information

        📸 PHOTOS:
        ────────────────────────────────────────────────────────────
        1. Mount iPhone: /etc/mount-iphone.sh
        2. Photos location: ~/iPhone/DCIM/
        3. Copy photos to your computer
        4. Unmount: /etc/unmount-iphone.sh

        Alternative: Use iCloud Photos via web browser at icloud.com

        💬 MESSAGES (iMessage):
        ────────────────────────────────────────────────────────────
        Unfortunately, iMessage is locked to Apple's ecosystem and
        cannot be accessed natively on Linux.

        Options:
        1. Use iCloud.com in web browser (limited functionality)
        2. Use your iPhone as normal for messaging
        3. Consider cross-platform messaging apps:
           - Signal, Telegram, WhatsApp (web versions available)

        📁 FILE TRANSFER:
        ────────────────────────────────────────────────────────────
        Mount filesystem:
          1. Run: /etc/mount-iphone.sh
          2. Access files in: ~/iPhone/
          3. Copy files to/from the mounted directory
          4. Unmount: /etc/unmount-iphone.sh

        🔧 USEFUL COMMANDS:
        ────────────────────────────────────────────────────────────
        ideviceinfo          # Show device information
        idevicepair pair     # Pair with iPhone (first time)
        idevicepair unpair   # Unpair device
        ifuse ~/iPhone       # Mount iPhone to ~/iPhone
        fusermount -u ~/iPhone  # Unmount iPhone
        idevicebackup2 backup ~/iphone-backup  # Backup iPhone
        ideviceinstaller -l  # List installed apps

        🐛 TROUBLESHOOTING:
        ────────────────────────────────────────────────────────────
        If iPhone not detected:
        1. Make sure iPhone is unlocked
        2. Tap "Trust" on iPhone when prompted
        3. Check usbmuxd service: systemctl status usbmuxd
        4. Try unpairing and re-pairing: idevicepair unpair && idevicepair pair

        If mounting fails:
        1. Make sure you're in the plugdev group: groups $USER
        2. If not, add yourself: sudo usermod -a -G plugdev $USER
           (then log out and back in)

        📚 DOCUMENTATION:
        ────────────────────────────────────────────────────────────
        libimobiledevice: https://libimobiledevice.org/

        ══════════════════════════════════════════════════════════════
      '';
      mode = "0644";
    };
  };
}
