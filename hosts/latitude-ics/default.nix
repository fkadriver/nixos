{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      ./syncthing.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.laptop-kde-ics
      inputs.self.nixosModules.vmware
      inputs.self.nixosModules.logitech
      inputs.self.nixosModules.multi-monitor
      inputs.self.nixosModules.user-scott
    ];
    config = {
      networking = {
        hostName = "latitude-ics";
      };

      # Static IP on USB network adapter (ICS lab network segment)
      networking.interfaces."enp0s20f0u1u4" = {
        useDHCP = false;
        ipv4.addresses = [{
          address = "192.168.0.2";
          prefixLength = 24;
        }];
      };

      services.vmware-host = {
        enable = true;
        bridgeInterface = "enp0s20f0u1u4";
        sharedFolders = [{
          hostPath = "/home/scott/Documents/SANS/ics/515/capstone";
          name = "ics515-capstone";
        }];
      };

      environment.systemPackages = [
        pkgs.rustdesk
        pkgs.geany
        pkgs.git-lfs
        pkgs.input-leap
      ];

      # Input Leap KVM and RustDesk remote desktop
      networking.firewall.allowedTCPPorts = [ 24800 ];
      networking.firewall.interfaces."tailscale0".allowedTCPPortRanges = [
        { from = 21115; to = 21119; }
      ];
      networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 21116 ];

      xdg.mime.defaultApplications = {
        "text/plain" = "geany.desktop";
        "text/x-config" = "geany.desktop";
      };

      systemd.user.services.input-leap-server = {
        description = "Input Leap keyboard/mouse sharing server";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.input-leap}/bin/input-leaps --no-daemon";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };

      systemd.user.services.rustdesk = {
        description = "RustDesk Remote Desktop daemon";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
          Restart = "on-failure";
        };
      };

      system = {
        stateVersion = "25.11";
      };
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
