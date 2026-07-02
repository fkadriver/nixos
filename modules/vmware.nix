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

    # VNET_0_INTERFACE sets the preferred bridge interface. vmnet-bridge may temporarily
    # switch to another interface (e.g. WiFi) at boot, but switches back to the configured
    # interface once it comes up. answer directives must go here, NOT in /etc/vmware/config.
    environment.etc."vmware/networking" = lib.mkIf (cfg.bridgeInterface != null) {
      mode = "0644";
      text = ''
        VERSION=1,0
        answer VNET_0_INTERFACE ${cfg.bridgeInterface}
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
