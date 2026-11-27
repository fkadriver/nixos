# NUT (Network UPS Tools) server for the closet UPS (CyberPower CP1500PFCLCD,
# USB 0764:0601, usbhid-ups driver). The host with the UPS's USB cable runs
# the driver + upsd and is the upsmon primary. Other hosts and Home Assistant
# read it over Tailscale on port 3493.
#
# Lives on vm01 for now (that's where the cable is, 2026-11-27); the plan
# (jen-acres-network-docs 12_UPS_POWER.md) is to move the cable and this
# module to nas01, so nas01's own shutdown never depends on the network.
#
# Same access pattern as shutdown-listener.nix: upsd binds all addresses but
# the firewall only opens 3493 on tailscale0, so HA (IoT VLAN) reaches it
# without a VLAN firewall hole, and binding 0.0.0.0 avoids racing tailscale0
# coming up at boot.
#
# Passwords are generated on the host on first start (/var/lib/nut-passwords,
# root-only), not kept in sops: nothing but upsd and its clients need them.
# Read the HA one with `sudo cat /var/lib/nut-passwords/homeassistant`.
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.nutServer;
  pwDir = "/var/lib/nut-passwords";
in
{
  options.services.nutServer = {
    enable = lib.mkEnableOption "NUT server for the closet UPS over USB";

    upsName = lib.mkOption {
      type = lib.types.str;
      default = "closet";
      description = "NUT name of the UPS (clients use <name>@<host>).";
    };

    killPower = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Tell the UPS to cut its outlets at the end of this host's low-battery
        shutdown (so everything reboots when mains returns). Only safe on the
        last host to go down (nas01), once every other host is a NUT client.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    power.ups = {
      enable = true;
      mode = "netserver";

      ups.${cfg.upsName} = {
        driver = "usbhid-ups";
        port = "auto";
        description = "CyberPower CP1500PFCLCD (server closet)";
        directives = [
          "vendorid = 0764"
          "productid = 0601"
        ];
      };

      upsd.listen = [
        { address = "0.0.0.0"; port = 3493; }
      ];

      users = {
        upsmon = {
          passwordFile = "${pwDir}/upsmon";
          upsmon = "primary";
        };
        # Read-only account for HA's NUT integration (no actions/instcmds).
        homeassistant = {
          passwordFile = "${pwDir}/homeassistant";
        };
      };

      upsmon.monitor.${cfg.upsName} = {
        system = "${cfg.upsName}@localhost";
        user = "upsmon";
        passwordFile = "${pwDir}/upsmon";
        type = "primary";
      };

      upsmon.settings.POWERDOWNFLAG = lib.mkIf (!cfg.killPower) (lib.mkForce null);
    };

    systemd.services.nut-passwords = {
      description = "Generate NUT user passwords on first boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "upsd.service" "upsmon.service" ];
      requiredBy = [ "upsd.service" "upsmon.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 ${pwDir}
        for u in upsmon homeassistant; do
          f=${pwDir}/$u
          if [ ! -s "$f" ]; then
            ${pkgs.openssl}/bin/openssl rand -hex 16 > "$f"
            chmod 0600 "$f"
          fi
        done
      '';
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 3493 ];
  };
}
