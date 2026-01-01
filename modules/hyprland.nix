{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    ./hyprland-config.nix
  ];

  config = {
    # Enable Hyprland Wayland compositor
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

    # Enable graphics drivers
    hardware.graphics.enable = true;

    # Environment variables for Wayland
    environment.sessionVariables = {
      # Force Wayland backend for applications
      NIXOS_OZONE_WL = "1";  # Chromium/Electron apps
      MOZ_ENABLE_WAYLAND = "1";  # Firefox
      QT_QPA_PLATFORM = "wayland";  # Qt applications
      GDK_BACKEND = "wayland";  # GTK applications
      SDL_VIDEODRIVER = "wayland";  # SDL applications
      CLUTTER_BACKEND = "wayland";  # Clutter applications

      # XDG specifications
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
    };

    # Display manager for login
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          # Create a proper session wrapper for Hyprland
          command = let
            hyprland-session = pkgs.writeShellScript "hyprland-session" ''
              # Source the system environment
              . /etc/profile

              # Clean up stale Wayland lock files
              rm -f $XDG_RUNTIME_DIR/wayland-*.lock

              # Set up XDG directories
              export XDG_SESSION_TYPE=wayland
              export XDG_SESSION_DESKTOP=Hyprland
              export XDG_CURRENT_DESKTOP=Hyprland

              # Launch Hyprland
              exec Hyprland
            '';
          in "${lib.getExe pkgs.tuigreet} --time --remember --cmd ${hyprland-session}";
          user = "greeter";
        };
      };
    };

    # Essential packages for Hyprland environment
    environment.systemPackages = with pkgs; [
      # Hyprland is needed in PATH for greetd
      hyprland

      # Wayland tools
      wayland
      wayland-protocols
      wayland-utils
      wl-clipboard
      wl-clipboard-x11

      # Hyprland ecosystem
      hyprpaper  # Wallpaper utility
      hyprlock   # Screen locker
      hypridle   # Idle daemon
      hyprpicker # Color picker

      # Status bar
      waybar

      # App launcher
      rofi

      # Notifications
      dunst
      libnotify

      # Screenshot/screencast
      grim       # Screenshot tool
      slurp      # Screen area selection
      wf-recorder # Screen recording

      # System utilities
      brightnessctl  # Brightness control
      wireplumber    # Audio control (needed for wpctl)

      # File manager
      xfce.thunar
      xfce.thunar-volman
      xfce.thunar-archive-plugin

      # Terminal
      kitty

      # Network management GUI
      networkmanagerapplet

      # Audio control
      pavucontrol

      # Image viewer
      imv

      # PDF viewer
      zathura

      # Qt theming
      qt5.qtwayland
      qt6.qtwayland
      libsForQt5.qtstyleplugin-kvantum

      # GTK theming
      gnome-themes-extra
      adwaita-icon-theme
    ];

    # XDG Portal for screen sharing and file pickers
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
      config.common.default = "*";
    };

    # Qt theming to match GTK
    qt = {
      enable = true;
      platformTheme = "gnome";
      style = "adwaita-dark";
    };

    # Sound server (PipeWire)
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Printing support
    services.printing.enable = true;

    # Enable dbus for inter-process communication
    services.dbus.enable = true;

    # Polkit for privilege escalation
    security.polkit.enable = true;

    # GNOME Keyring for credential storage
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;

    # Fonts
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      font-awesome
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
    ];

    # Network management
    networking.networkmanager.enable = true;
  };
}
