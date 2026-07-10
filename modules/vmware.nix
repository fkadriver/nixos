{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.vmware-host;
in
{
  options.services.vmware-host = {
    bridgeInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Network interface to bridge vmnet0 to. Null leaves vmnet0 in NAT mode.";
      example = "enp0s20u2u4";
    };

    hostAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static IPv4 address for the bridge interface. Null uses DHCP.";
      example = "192.168.0.2";
    };

    prefixLength = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Prefix length for hostAddress.";
    };

    sharedFolders = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          hostPath = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path on the host to share with all VMs.";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Share name as it appears inside VMs.";
          };
          readOnly = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
      });
      default = [];
      description = "Host directories to expose to all VMs via VMware shared folders.";
    };
  };

  config = {
    environment.systemPackages = [ pkgs.vmware-workstation ];

    virtualisation.vmware.host.enable = true;

    # VNET_0_INTERFACE alone is only a soft preference: vmnet-bridge re-runs auto-sensing
    # on route changes and steals the bridge for the default-route interface (seen on
    # OTworkstation: WiFi came up 2s after eno1 at boot and took vmnet0 permanently).
    # add_bridge_mapping statically pins the interface to vmnet0, disabling auto-sensing.
    # answer directives must go here, NOT in /etc/vmware/config.
    environment.etc."vmware/networking" = lib.mkIf (cfg.bridgeInterface != null) {
      mode = "0644";
      text = ''
        VERSION=1,0
        answer VNET_0_INTERFACE ${cfg.bridgeInterface}
        add_bridge_mapping ${cfg.bridgeInterface} 0
        answer VNET_0_DHCP no
        answer VNET_0_VIRTUAL_ADAPTER no
        answer VNET_1_DHCP yes
        answer VNET_1_HOSTONLY_NETMASK 255.255.255.0
        answer VNET_1_HOSTONLY_SUBNET 192.168.208.0
        answer VNET_1_VIRTUAL_ADAPTER yes
        answer VNET_8_DHCP yes
        answer VNET_8_HOSTONLY_NETMASK 255.255.255.0
        answer VNET_8_HOSTONLY_SUBNET 192.168.182.0
        answer VNET_8_NAT yes
        answer VNET_8_VIRTUAL_ADAPTER yes
      '';
    };

    # vmware-networks spawns vmnet-bridge in auto-sensing mode, which steals the
    # bridge for the default-route interface (e.g. WiFi) on any route change —
    # VNET_0_INTERFACE and add_bridge_mapping do not prevent this (verified on
    # OTworkstation, 2026-07-10). Replace it with a daemon pinned via -i, which
    # restricts the candidate set to the configured interface.
    systemd.services.vmnet-bridge-pin = lib.mkIf (cfg.bridgeInterface != null) {
      description = "vmnet0 bridge pinned to ${cfg.bridgeInterface}";
      after = [ "vmware-networks.service" ];
      requires = [ "vmware-networks.service" ];
      partOf = [ "vmware-networks.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        PIDFile = "/run/vmnet-bridge-0.pid";
        ExecStartPre = [
          "-${pkgs.procps}/bin/pkill -x vmnet-bridge"
          "${pkgs.coreutils}/bin/sleep 1"
        ];
        ExecStart = "${pkgs.vmware-workstation}/bin/vmnet-bridge -n0 -i${cfg.bridgeInterface} -d/run/vmnet-bridge-0.pid";
        Restart = "on-failure";
      };
    };

    networking.interfaces = lib.mkIf (cfg.bridgeInterface != null && cfg.hostAddress != null) {
      ${cfg.bridgeInterface} = {
        useDHCP = false;
        ipv4.addresses = [{
          address = cfg.hostAddress;
          prefixLength = cfg.prefixLength;
        }];
      };
    };
  };
}
