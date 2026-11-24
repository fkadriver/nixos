{ config, lib, pkgs, ... }:

# Airbook desktop: a macOS-style Plank dock and default applications, matching
# the airbook-darwin dock (bottom, autohide, 48px) and app choices.
#
# Everything here is a system-level default: Plank's settings go in a dconf
# system database and the default apps in /etc/xdg. A change made in the
# Plank or XFCE preferences GUI is saved per user and wins over these
# defaults, so remove ~/.config/dconf/user keys, ~/.config/mimeapps.list or
# ~/.config/xfce4/helpers.rc to fall back to what's declared here.

let
  # Dock order, left to right: desktop file name -> .dockitem name.
  dockApps = [
    { item = "firefox"; desktop = "firefox.desktop"; }
    { item = "thunderbird"; desktop = "thunderbird.desktop"; }
    { item = "ghostty"; desktop = "com.mitchellh.ghostty.desktop"; }
    { item = "thunar"; desktop = "thunar.desktop"; }
    # MTGA (Heroic/Epic app "stargazer") goes here once its Heroic setup is
    # done. Heroic makes no menu entry for it, so it'll need a makeDesktopItem
    # with exec: heroic --no-gui "heroic://launch?appName=stargazer&runner=legendary"
  ];

  dockItem = app: pkgs.writeText "${app.item}.dockitem" ''
    [PlankDockItemPreferences]
    Launcher=file:///run/current-system/sw/share/applications/${app.desktop}
  '';

  # XFCE's "preferred applications" only lists terminals it ships a helper
  # for, and Ghostty isn't one, so add the helper.
  ghosttyHelper = pkgs.writeTextDir "share/xfce4/helpers/ghostty.desktop" ''
    [Desktop Entry]
    NoDisplay=true
    Version=1.0
    Type=X-XFCE-Helper
    X-XFCE-Category=TerminalEmulator
    Name=Ghostty
    Icon=com.mitchellh.ghostty
    X-XFCE-Commands=ghostty
    X-XFCE-CommandsWithParameter=ghostty -e "%s"
  '';
in
{
  environment.systemPackages = [ pkgs.plank ghosttyHelper ];

  # Start the dock with the XFCE session.
  environment.etc."xdg/autostart/plank.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Plank
    Comment=Dock
    Exec=plank
    Icon=plank
    Terminal=false
    X-GNOME-Autostart-enabled=true
  '';

  programs.dconf.profiles.user.databases = [{
    settings."net/launchpad/plank/docks/dock1" = {
      dock-items = map (app: "${app.item}.dockitem") dockApps;
      position = "bottom";
      hide-mode = "auto";        # darwin: autohide = true
      hide-delay = lib.gvariant.mkInt32 0;      # darwin: autohide-delay = 0
      unhide-delay = lib.gvariant.mkInt32 0;
      icon-size = lib.gvariant.mkInt32 48;      # darwin: tilesize = 48
      zoom-enabled = false;
      theme = "Transparent";
    };
  }];

  # Plank reads launchers from per-user .dockitem files. `L` only creates a
  # link when nothing is there, so items the user customises are left alone.
  systemd.user.tmpfiles.users.scott.rules =
    [ "d %h/.config/plank/dock1/launchers 0755 - - -" ]
    ++ map (app: "L %h/.config/plank/dock1/launchers/${app.item}.dockitem - - - - ${dockItem app}") dockApps;

  # Default applications — same choices as airbook-darwin.
  xdg.mime.defaultApplications = let
    browser = "firefox.desktop";
    mail = "thunderbird.desktop";
    text = "org.xfce.mousepad.desktop";
    pdf = "org.gnome.Evince.desktop";
    image = "org.xfce.ristretto.desktop";
    video = "mpv.desktop";
  in {
    "text/html" = browser;
    "application/xhtml+xml" = browser;
    "x-scheme-handler/http" = browser;
    "x-scheme-handler/https" = browser;
    "x-scheme-handler/about" = browser;
    "x-scheme-handler/unknown" = browser;

    "x-scheme-handler/mailto" = mail;
    "message/rfc822" = mail;
    "text/calendar" = mail;

    "inode/directory" = "thunar.desktop";

    "text/plain" = text;
    "text/x-config" = text;
    "text/markdown" = text;
    "application/x-shellscript" = text;

    "application/pdf" = pdf;

    "image/png" = image;
    "image/jpeg" = image;
    "image/gif" = image;
    "image/webp" = image;
    "image/bmp" = image;
    "image/tiff" = image;

    "video/mp4" = video;
    "video/x-matroska" = video;
    "video/webm" = video;
    "video/quicktime" = video;
    "video/x-msvideo" = video;
    "audio/mpeg" = video;
    "audio/flac" = video;
    "audio/ogg" = video;
  };

  # XFCE's own preferred-application helpers (used by exo-open, Thunar's
  # "Open Terminal Here", the Whisker menu's browser/terminal launchers).
  environment.etc."xdg/xfce4/helpers.rc".text = ''
    WebBrowser=firefox
    MailReader=thunderbird
    FileManager=thunar
    TerminalEmulator=ghostty
  '';

  # Terminal for apps that use xdg-terminal-exec (desktop entries with
  # Terminal=true).
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "com.mitchellh.ghostty.desktop" ];
  };
}
