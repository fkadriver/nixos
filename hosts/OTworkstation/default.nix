{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.sops-nix.nixosModules.sops
      inputs.self.nixosModules.common
      inputs.self.nixosModules.syncthing
      inputs.self.nixosModules.laptop-minimal
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.virtualbox
      inputs.self.nixosModules.vmware
      inputs.self.nixosModules.wireless
    ];
    config = {
      networking.hostName = "OTworkstation";

      # VMware: bridge built-in NIC (eno1) to vmnet0 for RELICS ICS lab VMs
      # Static IP is managed by the C3PO NetworkManager profile below.
      services.vmware-host.bridgeInterface = "eno1";

      # SSH server — key-only auth
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      # Open SSH on all interfaces (tailscale.nix trusts tailscale0; this covers LAN/direct)
      networking.firewall.allowedTCPPorts = [ 22 ];

      # xrdp remote desktop — openbox session, accessible on all interfaces (opens port 3389)
      # xfce4-session is a singleton; it's already running on the physical display via lightdm,
      # so xrdp sessions use openbox instead to avoid the conflict.
      services.xrdp = {
        enable = true;
        defaultWindowManager = "${pkgs.dbus}/bin/dbus-launch --exit-with-session ${pkgs.openbox}/bin/openbox-session";
        openFirewall = true;
      };

      environment.systemPackages = with pkgs; [
        openbox   # window manager for xrdp sessions
        xterm     # terminal emulator accessible via openbox right-click menu
      ];

      # C3PO wired profile — eno1 (built-in NIC) with static 192.168.0.2/24, no gateway.
      # Bridges into the RELICS ICS lab network via VMware vmnet0.
      environment.etc."NetworkManager/system-connections/C3PO.nmconnection" = {
        mode = "0600";
        text = ''
          [connection]
          id=C3PO
          uuid=0bf931d4-e71e-4754-9936-9e0a8e64c2b8
          type=802-3-ethernet
          interface-name=eno1
          autoconnect=true

          [ethernet]
          auto-negotiate=true
          mac-address=F8:CA:B8:2B:C9:1A

          [ipv4]
          method=manual
          address1=192.168.0.2/24

          [ipv6]
          addr-gen-mode=stable-privacy
          method=auto
        '';
      };

      # Openbox right-click menu for xrdp sessions
      environment.etc."xdg/openbox/menu.xml" = {
        text = ''
          <?xml version="1.0" encoding="UTF-8"?>
          <openbox_menu xmlns="http://openbox.org/"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://openbox.org/ file:///usr/share/openbox/menu.xsd">
          <menu id="root-menu" label="OTWorkstation">
            <item label="VMware Workstation">
              <action name="Execute"><execute>vmware</execute></action>
            </item>
            <item label="Terminal">
              <action name="Execute"><execute>xterm</execute></action>
            </item>
            <separator/>
            <menu id="client-list-menu"/>
            <separator/>
            <item label="Reconfigure">
              <action name="Reconfigure"/>
            </item>
            <item label="Log Out">
              <action name="Exit"/>
            </item>
          </menu>
          </openbox_menu>
        '';
      };

      sops.age.keyFile = "/var/lib/sops-nix/key.txt";

      system.activationScripts.sops-nix-setup = lib.mkBefore ''
        if [ ! -f /var/lib/sops-nix/key.txt ]; then
          mkdir -p /var/lib/sops-nix
          ${pkgs.age}/bin/age-keygen -o /var/lib/sops-nix/key.txt
          chmod 600 /var/lib/sops-nix/key.txt
          echo "Generated new age key for sops-nix at /var/lib/sops-nix/key.txt"
          echo "Public key: $(${pkgs.age}/bin/age-keygen -y /var/lib/sops-nix/key.txt)"
        fi
      '';

      system.stateVersion = "25.11";
    };
  };
in
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    nixosModule
  ];
  system = "x86_64-linux";
}
