{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.forscan;

  wine = cfg.winePackage;

  # Wrapper that manages the wine prefix, symlinks the OBD adapter to COM1,
  # and launches FORScan. FORScan itself is not packaged (license requires
  # downloading the installer from forscan.org), so first-time setup goes:
  #   1. forscan install /path/to/FORScanSetup.exe
  #   2. forscan
  forscanScript = pkgs.writeShellScriptBin "forscan" ''
    set -euo pipefail

    export WINEPREFIX="''${WINEPREFIX:-$HOME/.local/share/forscan-wine}"
    export WINEDEBUG="''${WINEDEBUG:-fixme-all,err-winediag}"

    wine=${wine}/bin/wine
    wineboot=${wine}/bin/wineboot

    # OBDLink EX may enumerate as FTDI (ttyUSB) or STM32 CDC-ACM (ttyACM)
    # depending on firmware. udev creates /dev/obdlink-ex when either matches.
    device="''${FORSCAN_DEVICE:-}"
    if [ -z "$device" ]; then
      for candidate in /dev/obdlink-ex /dev/ttyUSB0 /dev/ttyACM0; do
        if [ -e "$candidate" ]; then
          device="$candidate"
          break
        fi
      done
    fi

    if [ ! -d "$WINEPREFIX" ]; then
      echo "Initializing Wine prefix at $WINEPREFIX ..." >&2
      "$wineboot" --init
    fi

    if [ -n "$device" ]; then
      mkdir -p "$WINEPREFIX/dosdevices"
      ln -sfn "$device" "$WINEPREFIX/dosdevices/com1"
    else
      echo "warning: no OBD adapter found (looked for /dev/obdlink-ex, ttyUSB0, ttyACM0)" >&2
      echo "         plug in the OBDLink EX or set FORSCAN_DEVICE=/dev/ttyXXX" >&2
    fi

    case "''${1:-}" in
      install)
        if [ -z "''${2:-}" ]; then
          echo "usage: forscan install /path/to/FORScanSetup.exe" >&2
          exit 2
        fi
        exec "$wine" "$2"
        ;;
      wine)
        shift
        exec "$wine" "$@"
        ;;
      "")
        exe="$(find "$WINEPREFIX/drive_c" -iname 'FORScan.exe' 2>/dev/null | head -n1 || true)"
        if [ -z "$exe" ]; then
          cat >&2 <<EOF
FORScan is not installed in $WINEPREFIX.

To install:
  1. Download FORScanSetup.exe from https://forscan.org/download.html
  2. forscan install /path/to/FORScanSetup.exe
  3. forscan

If FORScan complains about missing .NET, run:
  forscan wine winetricks dotnet40
EOF
          exit 1
        fi
        exec "$wine" "$exe"
        ;;
      *)
        echo "usage: forscan [install <installer.exe> | wine <args...>]" >&2
        exit 2
        ;;
    esac
  '';
in
{
  options.services.forscan = {
    enable = lib.mkEnableOption "FORScan (Ford/Lincoln/Mazda OBD-II diagnostics) via Wine";

    user = lib.mkOption {
      type = lib.types.str;
      default = "scott";
      description = "User added to the dialout group for OBD adapter access.";
    };

    winePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wineWow64Packages.stable;
      defaultText = lib.literalExpression "pkgs.wineWow64Packages.stable";
      description = "Wine build used to run FORScan.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      wine
      pkgs.winetricks
      forscanScript
    ];

    # Stable /dev/obdlink-ex symlink and dialout ownership regardless of
    # which chipset the adapter presents.
    services.udev.extraRules = ''
      # OBDLink EX — FTDI FT232 variant
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", GROUP="dialout", MODE="0660", SYMLINK+="obdlink-ex"
      # OBDLink EX — STM32 CDC-ACM variant
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", GROUP="dialout", MODE="0660", SYMLINK+="obdlink-ex"
    '';

    users.groups.dialout = {};
    users.users.${cfg.user}.extraGroups = [ "dialout" ];
  };
}
