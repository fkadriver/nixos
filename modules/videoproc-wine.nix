{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# EXPERIMENTAL: VideoProc Converter AI (Digiarty, Windows-only) under Wine.
# Same shape as forscan.nix: the installer isn't packaged (proprietary,
# downloaded from videoproc.com), so the wrapper only manages a dedicated
# Wine prefix and launches whatever is installed in it.
#
#   videoproc install ~/Downloads/videoproc-converter-ai.exe
#   videoproc                 # launch
#   videoproc debug           # launch with a Wine log in ~/videoproc-wine.log
#   videoproc winetricks dxvk # extra Windows components into the prefix
#   videoproc wine <args>     # raw wine in the prefix
#   videoproc reset           # delete the prefix and start over
#
# Expectations: the GUI and plain software (CPU) transcoding are the parts
# most likely to work. Hardware encode (NVENC/QSV/AMF) and the AI features
# depend on Windows GPU APIs that Wine supports poorly or not at all. See
# docs/videoproc-wine.md for test notes.
let
  cfg = config.programs.videoprocWine;
  wine = cfg.winePackage;

  videoprocScript = pkgs.writeShellScriptBin "videoproc" ''
    set -euo pipefail

    export WINEPREFIX="''${VIDEOPROC_PREFIX:-$HOME/.local/share/videoproc-wine}"
    export WINEARCH=win64
    export WINEDEBUG="''${WINEDEBUG:-fixme-all,err-winediag}"
    export PATH=${lib.makeBinPath [ wine pkgs.winetricks pkgs.cabextract pkgs.unzip ]}:$PATH

    init_prefix() {
      if [ ! -d "$WINEPREFIX" ]; then
        echo "Initializing Wine prefix at $WINEPREFIX ..." >&2
        wineboot --init
        # VideoProc's installer refuses anything older than Windows 10.
        wine reg add 'HKCU\Software\Wine' /v Version /d win10 /f >/dev/null
        wineserver -w
      fi
    }

    find_exe() {
      if [ -n "''${VIDEOPROC_EXE:-}" ]; then
        echo "$VIDEOPROC_EXE"
        return
      fi
      find "$WINEPREFIX/drive_c" -type f -iname 'VideoProc*.exe' \
        ! -iname '*unins*' ! -iname '*setup*' ! -iname '*update*' 2>/dev/null \
        | head -n1 || true
    }

    launch() {
      exe="$(find_exe)"
      if [ -z "$exe" ]; then
        cat >&2 <<EOF
VideoProc Converter AI is not installed in $WINEPREFIX.

  1. Download the Windows installer from https://www.videoproc.com/
  2. videoproc install /path/to/installer.exe
  3. videoproc

If the main exe isn't found automatically, set VIDEOPROC_EXE to its path.
EOF
        exit 1
      fi
      cd "$(dirname "$exe")"
      exec wine "$exe" "$@"
    }

    cmd="''${1:-}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
      install)
        [ -n "''${1:-}" ] || { echo "usage: videoproc install <installer.exe>" >&2; exit 2; }
        init_prefix
        exec wine "$1"
        ;;
      "")
        init_prefix
        launch
        ;;
      debug)
        init_prefix
        log="$HOME/videoproc-wine.log"
        echo "Logging to $log" >&2
        export WINEDEBUG="err+all,warn+module,warn+loaddll,fixme-all"
        launch "$@" 2>"$log"
        ;;
      wine)
        init_prefix
        exec wine "$@"
        ;;
      winetricks)
        init_prefix
        exec winetricks "$@"
        ;;
      winecfg)
        init_prefix
        exec winecfg
        ;;
      reset)
        wineserver -k 2>/dev/null || true
        read -r -p "Delete $WINEPREFIX? [y/N] " ans
        [ "$ans" = y ] && rm -rf "$WINEPREFIX" && echo "Removed." >&2
        ;;
      *)
        echo "usage: videoproc [install <exe> | debug | wine <args> | winetricks <verbs> | winecfg | reset]" >&2
        exit 2
        ;;
    esac
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "videoproc-wine";
    desktopName = "VideoProc Converter AI (Wine)";
    comment = "Experimental: VideoProc Converter AI running under Wine";
    exec = "videoproc";
    icon = "video-x-generic";
    categories = [ "AudioVideo" "Video" ];
  };
in
{
  options.programs.videoprocWine = {
    enable = lib.mkEnableOption "experimental VideoProc Converter AI wrapper under Wine";

    winePackage = lib.mkOption {
      type = lib.types.package;
      # Staging carries more D3D/media patches than stable, which is what an
      # app like this is most likely to trip over.
      default = pkgs.wineWow64Packages.staging;
      defaultText = lib.literalExpression "pkgs.wineWow64Packages.staging";
      description = "Wine build used to run VideoProc.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      videoprocScript
      desktopItem
    ];
  };
}
