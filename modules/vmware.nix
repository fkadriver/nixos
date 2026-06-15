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
      example = "enp0s20f0u1u4";
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
  };
}
