{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
  imports = [
    inputs.self.nixosModules.daily-driver
  ];

  config = {
    # Set boot label
    system.nixos.label = "XFCE";

    # Enable X11 and XFCE
    services.xserver = {
      enable = true;
      displayManager.lightdm.enable = true;
      desktopManager.xfce = {
        enable = true;
        enableXfwm = true;
        enableScreensaver = true;
      };
      # Screen saver timeout (15 minutes = 900 seconds)
      serverFlagsSection = ''
        Option "BlankTime" "15"
        Option "StandbyTime" "15"
        Option "SuspendTime" "15"
        Option "OffTime" "15"
      '';
    };

    # Blueman GUI for XFCE
    services.blueman.enable = true;

    # XFCE-specific apps/plugins (appended to daily-driver list)
    environment.systemPackages = lib.mkAfter (with pkgs; [
      # Office / viewers (XFCE side)
      evince

      # Utilities
      xarchiver
      xdotool
      xbindkeys
      xorg.xev

      # XFCE plugins and utilities
      xfce4-battery-plugin
      xfce4-clipman-plugin
      xfce4-cpugraph-plugin
      xfce4-netload-plugin
      xfce4-pulseaudio-plugin
      xfce4-screenshooter
      xfce4-systemload-plugin
      xfce4-taskmanager
      xfce4-weather-plugin
      xfce4-whiskermenu-plugin
      xfce4-xkb-plugin

      # Thunar file manager plugins
      thunar-archive-plugin
      thunar-volman
      thunar-media-tags-plugin

      # Additional XFCE apps
      ristretto
      mousepad

      # Prevent screen blanking/sleep
      caffeine-ng
    ]);
  };
}
