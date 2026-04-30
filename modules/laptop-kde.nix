{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
  imports = [
    inputs.self.nixosModules.daily-driver
  ];

  config = {
    # Set boot label
    system.nixos.label = "KDE";

    # Enable KDE Plasma
    services.xserver.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;

    # KDE Connect for phone integration
    programs.kdeconnect.enable = true;

    # PipeWire for audio (KDE integrates well with PipeWire)
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Disable power-profiles-daemon to avoid conflict with TLP (if you use it elsewhere)
    services.power-profiles-daemon.enable = false;

    # KDE / Plasma apps and utilities (appended to daily-driver list)
    environment.systemPackages = lib.mkAfter (with pkgs; [
      # Media / viewing
      kdePackages.gwenview
      kdePackages.okular

      # Utilities
      kdePackages.ark
      kdePackages.kcalc
      kdePackages.spectacle
      kdePackages.filelight
      kdePackages.isoimagewriter  # Write .img/.iso files to USB drives
      usbimager                   # Minimal GUI for writing .img files to USB

      # KDE core
      kdePackages.dolphin
      kdePackages.konsole
      kdePackages.kate
      kdePackages.kcmutils
      kdePackages.kscreen
      kdePackages.plasma-systemmonitor
      kdePackages.kinfocenter
      kdePackages.plasma-nm
      kdePackages.plasma-pa
      kdePackages.bluedevil
      kdePackages.powerdevil
      kdePackages.kgamma

      # Networking tools
      wireshark

      # Prevent screen blanking/sleep
      caffeine-ng
    ]);

    # Auto-start caffeine to prevent screen blanking
    environment.etc."xdg/autostart/caffeine.desktop".text = ''
      [Desktop Entry]
      Name=Caffeine
      Comment=Prevent screen blanking
      Exec=caffeine
      Icon=caffeine
      Terminal=false
      Type=Application
      Categories=Utility;
      X-GNOME-Autostart-enabled=true
    '';

    # KDE Global Shortcuts - Ctrl+F7 for Spectacle (screenshot)
    # This creates/updates the kglobalshortcutsrc file for user scott
    system.activationScripts.kdeShortcuts = lib.stringAfter [ "users" ] ''
      SHORTCUTS_FILE="/home/scott/.config/kglobalshortcutsrc"

      mkdir -p /home/scott/.config

      if [ ! -f "$SHORTCUTS_FILE" ]; then
        touch "$SHORTCUTS_FILE"
        chown scott:users "$SHORTCUTS_FILE"
      fi

      if command -v ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 &> /dev/null; then
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$SHORTCUTS_FILE" \
          --group "org.kde.spectacle.desktop" \
          --key "RectangularRegionScreenShot" "Ctrl+F7,Meta+Shift+Print,Capture Rectangular Region"
      fi

      chown scott:users "$SHORTCUTS_FILE"
    '';
  };
}
