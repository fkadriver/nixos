{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.esphomeFlash;

  # ESP32 boards flashed here (M5Stack Atom Lite, etc.) use a CH340
  # USB-serial chip - stable /dev/esp32-flash symlink regardless of which
  # ttyUSBn/ttyACMn node the kernel assigns on a given plug-in.
  flashScript = pkgs.writeShellScriptBin "esphome-flash" ''
    set -euo pipefail

    if [ $# -lt 1 ]; then
      echo "usage: esphome-flash <config.yaml> [esphome args...]" >&2
      exit 2
    fi

    config="$1"
    shift

    if [ ! -e /dev/esp32-flash ]; then
      echo "error: /dev/esp32-flash not found - is the board plugged in?" >&2
      echo "       (expects a CH340 USB-serial chip, idVendor=1a86 idProduct=7523)" >&2
      exit 1
    fi

    exec ${pkgs.esphome}/bin/esphome run "$config" --device /dev/esp32-flash "$@"
  '';
in
{
  options.services.esphomeFlash = {
    enable = lib.mkEnableOption "ESPHome CLI + USB-serial access for flashing ESP32 boards (Bluetooth proxies, etc.)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "scott";
      description = "User added to the dialout group for serial access.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.esphome
      flashScript
    ];

    # M5Stack Atom Lite's onboard CH340 USB-serial chip (confirmed via lsusb:
    # "1a86:7523 QinHeng Electronics CH340 serial converter"). Same rule
    # covers other ESP32 dev boards using the same common chip.
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", GROUP="dialout", MODE="0660", SYMLINK+="esp32-flash"
    '';

    users.groups.dialout = {};
    users.users.${cfg.user}.extraGroups = [ "dialout" ];
  };
}
