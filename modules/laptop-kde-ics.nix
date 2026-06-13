{ inputs, ... }@flakeContext:
# KDE Plasma desktop for ICS workstation — omits 3d-printing, font, games, iphone.
# Includes bitwarden, borg-backup, printing, syncthing, vscode, and home-manager
# from daily-driver, but leaves out the extras not needed for ICS lab work.
{ config, lib, pkgs, ... }:
{
  imports = [
    inputs.self.nixosModules.printing
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.bitwarden-scott
    inputs.self.nixosModules.borg-backup
    inputs.self.nixosModules.syncthing-declarative
    inputs.self.nixosModules.vscode
    inputs.home-manager.nixosModules.home-manager
    (inputs.self.homeConfigurations.scott).nixosModule
  ];

  config = {
    system.nixos.label = "KDE";

    services.xserver.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;

    programs.kdeconnect.enable = true;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.power-profiles-daemon.enable = false;

    networking.networkmanager.enable = true;

    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';

    programs.firefox.enable = true;

    environment.systemPackages = with pkgs; [
      python3Minimal
      claude-code

      handbrake
      libreoffice
      thunderbird

      borgbackup
      unzip
      usbimager
      gparted

      brightnessctl

      # KDE utilities
      kdePackages.gwenview
      kdePackages.okular
      kdePackages.ark
      kdePackages.kcalc
      kdePackages.spectacle
      kdePackages.filelight
      kdePackages.isoimagewriter
      kdePackages.partitionmanager
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

      wireshark
      caffeine-ng
    ];

    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib zstd bzip2 xz
        openssl libxcrypt libxcrypt-legacy
        curl libssh
        util-linux systemd attr acl libsodium
        libxml2 glib dbus
        libGL
        libxcb
      ];
    };

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
