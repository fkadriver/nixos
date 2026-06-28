{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.vmware-host;
in
{
  options.services.vmware-host = {
    enable = lib.mkEnableOption "VMware Workstation host";

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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.vmware-workstation ];

    virtualisation.vmware.host = {
      enable = true;
      extraConfig =
        lib.optionalString (cfg.bridgeInterface != null) ''
          answer VMNET_0_INTERFACE ${cfg.bridgeInterface}
        ''
        + lib.concatMapStrings (sf: ''
          answer VMNET_SHAREDFOLDERS_FOLDER_${sf.name}_ENABLED yes
          answer VMNET_SHAREDFOLDERS_FOLDER_${sf.name}_PATH ${sf.hostPath}
          answer VMNET_SHAREDFOLDERS_FOLDER_${sf.name}_READONLY ${if sf.readOnly then "yes" else "no"}
        '') cfg.sharedFolders;
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
