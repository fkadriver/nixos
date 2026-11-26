{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  # Standalone apps that don't share a session/framework with KDE — safe on
  # the better-cached nixos-unstable input. kdePackages.* stay on the base
  # pkgs: they run inside the same Plasma session as services.desktopManager.plasma6
  # below, which always pulls from base pkgs with no override point, so
  # splitting just the app list would create Qt/KDE-frameworks version skew
  # against the shell they load into.
  pkgsNixos = inputs.nixpkgs-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  pinnedApps = config.desktop.kde.pinnedApps;

  # Plasma desktop script: set the launchers of every task manager widget
  # (icon-only or full) on every panel. `applications:<id>.desktop` resolves
  # through XDG_DATA_DIRS, so pins survive rebuilds and GC — pinning from the
  # GUI stores `file:///nix/store/...-system-path/...`, which goes stale.
  pinScript = pkgs.writeText "plasma-pinned-apps.js" ''
    var launchers = ${builtins.toJSON (map (id: "applications:${id}.desktop") pinnedApps)};
    panels().forEach(function (panel) {
      panel.widgets().forEach(function (w) {
        if (w.type == "org.kde.plasma.icontasks" || w.type == "org.kde.plasma.taskmanager") {
          w.currentConfigGroup = ["General"];
          w.writeConfig("launchers", launchers);
        }
      });
    });
  '';
in
{
  imports = [
    inputs.self.nixosModules.daily-driver
  ];

  options.desktop.kde.pinnedApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    # Captured from latitude's live panel 2026-11-26; shared by every KDE host.
    default = [
      "org.kde.konsole"
      "thunderbird"
      "org.kde.dolphin"
      "org.kde.krdc"
      "firefox"
      "com.mitchellh.ghostty"
    ];
    description = ''
      Desktop file IDs (without `.desktop`) pinned to the Plasma taskbar, left
      to right. Applied at every Plasma login, so pins changed in the GUI are
      reset; change this list instead. Set to `[ ]` to leave the taskbar alone.
    '';
  };

  config = {
    systemd.user.services.plasma-pinned-apps = lib.mkIf (pinnedApps != [ ]) {
      description = "Pin declared apps to the Plasma taskbar";
      # plasma-plasmashell is Type=dbus, so after it the shell's D-Bus API is up.
      after = [ "plasma-plasmashell.service" ];
      requisite = [ "plasma-plasmashell.service" ];
      wantedBy = [ "plasma-workspace.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "plasma-pinned-apps" ''
          exec ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript "$(< ${pinScript})"
        '';
      };
    };

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
    environment.systemPackages = lib.mkAfter ((with pkgs; [
      # Media / viewing
      kdePackages.gwenview
      kdePackages.okular

      # Utilities
      kdePackages.ark
      kdePackages.kcalc
      kdePackages.spectacle
      kdePackages.filelight
      kdePackages.isoimagewriter   # Write .img/.iso files to USB drives
      kdePackages.partitionmanager # Disk partitioning and formatting

      # KDE core
      kdePackages.dolphin
      kdePackages.konsole
      kdePackages.kate
      kdePackages.krdc             # remote desktop client (VNC/RDP), e.g. nas01-backup; pinned
      kdePackages.kcmutils
      kdePackages.kscreen
      kdePackages.plasma-systemmonitor
      kdePackages.kinfocenter
      kdePackages.plasma-nm
      kdePackages.plasma-pa
      kdePackages.bluedevil
      kdePackages.powerdevil
    ]) ++ (with pkgsNixos; [
      # Networking tools
      wireshark

      # Prevent screen blanking/sleep
      caffeine-ng
    ]));

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
    #
    # Ctrl+F7 is also KWin's default "Toggle Present Windows (Window class)"
    # shortcut ([kwin] ExposeClass). Both can't own the same combo — KWin's
    # built-in binding wins the conflict, so Ctrl+F7 silently did Present
    # Windows instead of launching Spectacle (confirmed 2026-10-06). Unbind
    # ExposeClass's active shortcut (leaving its recorded default alone) so
    # Spectacle gets sole ownership of Ctrl+F7.
    system.activationScripts.kdeShortcuts = lib.stringAfter [ "users" ] ''
      SHORTCUTS_FILE="/home/scott/.config/kglobalshortcutsrc"

      # Runs as root: create ~/.config owned by scott on a fresh install,
      # rather than `mkdir -p` leaving it root-owned.
      [ -d /home/scott/.config ] || install -d -o scott -g users -m 700 /home/scott/.config

      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$SHORTCUTS_FILE" \
        --group "org.kde.spectacle.desktop" \
        --key "RectangularRegionScreenShot" "Ctrl+F7,Meta+Shift+Print,Capture Rectangular Region"
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$SHORTCUTS_FILE" \
        --group "kwin" \
        --key "ExposeClass" "none,Ctrl+F7\tMeta+F7,Toggle Present Windows (Window class)"

      chown scott:users "$SHORTCUTS_FILE"
    '';
  };
}
