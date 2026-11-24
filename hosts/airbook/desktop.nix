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
  # XFCE's stock bottom panel sits on the same edge as Plank and does the same
  # job, so remove it. xfconf only falls back to the system panel layout when
  # a user has none, so this runs at each login against the user's own
  # config instead; once the panel is gone it's a no-op. It matches the stock
  # panel by its exact plugin list, not by number — XFCE reuses free panel
  # numbers, so a panel added later could be "panel-2" too and must survive.
  # Undo with: xfce4-panel --quit; pkill xfconfd; restore a backup of
  # ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml; xfce4-panel &
  removeStockBottomPanel = pkgs.writeShellApplication {
    name = "xfce-remove-stock-bottom-panel";
    runtimeInputs = [ pkgs.xfconf pkgs.xfce4-panel pkgs.coreutils pkgs.gnugrep pkgs.procps pkgs.util-linux ];
    text = ''
      q() { xfconf-query -c xfce4-panel "$@"; }
      ints() { grep -E '^[0-9]+$' || true; }

      # On a fresh account the panel writes its default layout as it starts,
      # possibly after this does.
      for _ in $(seq 30); do q -p /panels >/dev/null 2>&1 && break; sleep 1; done
      q -p /panels >/dev/null 2>&1 || exit 0

      stock="showdesktop separator launcher launcher launcher launcher separator directorymenu "
      keep=() remove=()
      for p in $(q -p /panels | ints); do
        types=""
        for id in $(q -p "/panels/panel-$p/plugin-ids" 2>/dev/null | ints); do
          types+="$(q -p "/plugins/plugin-$id" 2>/dev/null) "
        done
        if [ "$types" = "$stock" ]; then remove+=("$p"); else keep+=("$p"); fi
      done

      # Nothing to do, or it's the only panel left: leave it.
      [ "''${#remove[@]}" -gt 0 ] && [ "''${#keep[@]}" -gt 0 ] || exit 0

      args=()
      for p in "''${keep[@]}"; do args+=(-t int -s "$p"); done
      q -p /panels --force-array "''${args[@]}"
      for p in "''${remove[@]}"; do
        for id in $(q -p "/panels/panel-$p/plugin-ids" | ints); do
          q -p "/plugins/plugin-$id" -r -R
          rm -rf "$HOME/.config/xfce4/panel/launcher-$id"
        done
        q -p "/panels/panel-$p" -r -R
      done

      # -r only comes back if xfce4-session restarts the panel; a panel
      # started outside session management just quits. Start one ourselves
      # if none is back (a second instance exits on its own).
      xfce4-panel -r || true
      for _ in $(seq 10); do pgrep -x xfce4-panel >/dev/null && exit 0; sleep 1; done
      setsid xfce4-panel >/dev/null 2>&1 &
    '';
  };
in
{
  environment.systemPackages = [ pkgs.plank ghosttyHelper ];

  environment.etc."xdg/autostart/xfce-remove-stock-bottom-panel.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Remove XFCE stock bottom panel
    Comment=Plank replaces it (hosts/airbook/desktop.nix)
    Exec=${lib.getExe removeStockBottomPanel}
    OnlyShowIn=XFCE;
    NoDisplay=true
    Terminal=false
  '';

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
