{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }:
    let
      # CPU/MEM readout for the tint2 executor (runs every 2s)
      cpumem = pkgs.writeShellScript "tint2-cpumem" ''
        sample() {
          ${pkgs.gawk}/bin/awk '/^cpu /{idle=$5+$6; tot=0; for(i=2;i<=NF;i++)tot+=$i; print tot, idle}' /proc/stat
        }
        read -r t1 i1 <<< "$(sample)"
        ${pkgs.coreutils}/bin/sleep 1
        read -r t2 i2 <<< "$(sample)"
        dt=$((t2 - t1))
        cpu=0
        [ "$dt" -gt 0 ] && cpu=$(( (100 * (dt - (i2 - i1))) / dt ))
        mem=$(${pkgs.gawk}/bin/awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo)
        echo "CPU ''${cpu}%  MEM ''${mem}%"
      '';

      tint2rc = pkgs.writeText "tint2rc" ''
        # Background 1: panel
        rounded = 0
        border_width = 0
        background_color = #2e3440 100
        border_color = #2e3440 100

        # Background 2: active task
        rounded = 3
        border_width = 1
        background_color = #4c566a 100
        border_color = #88c0d0 100

        # Panel
        panel_items = TEC
        panel_size = 100% 30
        panel_position = bottom center horizontal
        panel_layer = top
        panel_background_id = 1
        panel_padding = 4 2 4
        wm_menu = 1

        # Taskbar
        taskbar_mode = single_desktop
        taskbar_padding = 2 2 4
        task_text = 1
        task_maximum_size = 200 30
        task_font_color = #d8dee9 100
        task_active_background_id = 2

        # Executor: CPU/MEM usage
        execp = new
        execp_command = ${cpumem}
        execp_interval = 2
        execp_has_icon = 0
        execp_font_color = #d8dee9 100
        execp_padding = 8 0

        # Clock
        time1_format = %H:%M
        clock_font_color = #d8dee9 100
        clock_padding = 8 0
      '';
    in
  {
    imports = [
      ./hardware.nix
      inputs.home-manager.nixosModules.home-manager
      (inputs.self.homeConfigurations.scott).nixosModule
      inputs.sops-nix.nixosModules.sops
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
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

      # Home-manager builds scott's dotfiles (.bashrc, .profile, starship, etc.)
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      # VMware: bridge built-in NIC (eno1) to vmnet0 for RELICS ICS lab VMs
      # Static IP is managed by the C3PO NetworkManager profile below.
      services.vmware-host.bridgeInterface = "eno1";

      # NAT the RELICS lab network (192.168.0.0/24 on eno1) out via WiFi so
      # lab VMs can reach the internet using 192.168.0.2 as their gateway.
      networking.nat = {
        enable = true;
        internalInterfaces = [ "eno1" ];
        externalInterface = "wlp2s0";
      };

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
      # QoL apps start from a session wrapper (not /etc/xdg/openbox/autostart:
      # nixpkgs' openbox-autostart hardcodes the store path for the global
      # autostart, so the /etc/xdg copy is never sourced).
      services.xrdp = {
        enable = true;
        defaultWindowManager = "${pkgs.writeShellScript "openbox-xrdp-session" ''
          ${pkgs.hsetroot}/bin/hsetroot -solid "#2e3440" &
          ${pkgs.tint2}/bin/tint2 -c ${tint2rc} &
          ${pkgs.xfce4-clipman-plugin}/bin/xfce4-clipman &
          exec ${pkgs.dbus}/bin/dbus-launch --exit-with-session ${pkgs.openbox}/bin/openbox-session
        ''}";
        openFirewall = true;
      };

      environment.systemPackages = with pkgs; [
        openbox   # window manager for xrdp sessions
        xterm     # fallback terminal
        tint2     # taskbar/panel for openbox xrdp sessions
        xfce4-clipman-plugin  # clipboard manager (standalone xfce4-clipman)
        hsetroot  # solid desktop background
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

      # Openbox rc.xml — stock config patched with launcher keybinds and
      # window snapping (W- is the Super/Windows key).
      environment.etc."xdg/openbox/rc.xml".source =
        pkgs.runCommand "openbox-rc.xml"
          {
            keybinds = ''
              <keybind key="W-t">
                <action name="Execute"><command>xfce4-terminal</command></action>
              </keybind>
              <keybind key="W-f">
                <action name="Execute"><command>firefox</command></action>
              </keybind>
              <keybind key="W-v">
                <action name="Execute"><command>vmware</command></action>
              </keybind>
              <keybind key="W-Up">
                <action name="Maximize"/>
              </keybind>
              <keybind key="W-Down">
                <action name="Unmaximize"/>
              </keybind>
              <keybind key="W-Left">
                <action name="Unmaximize"/>
                <action name="MoveResizeTo">
                  <x>0</x><y>0</y><width>50%</width><height>100%</height>
                </action>
              </keybind>
              <keybind key="W-Right">
                <action name="Unmaximize"/>
                <action name="MoveResizeTo">
                  <x>-0</x><y>0</y><width>50%</width><height>100%</height>
                </action>
              </keybind>
              </keyboard>
            '';
            passAsFile = [ "keybinds" ];
          } ''
          cp ${pkgs.openbox}/etc/xdg/openbox/rc.xml rc.xml
          chmod +w rc.xml
          substituteInPlace rc.xml \
            --replace-fail 'kfmclient openProfile filemanagement' 'thunar' \
            --replace-fail '<name>Konqueror</name>' '<name>Thunar</name>' \
            --replace-fail '</keyboard>' "$(cat "$keybindsPath")"
          cp rc.xml $out
        '';

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
            <item label="Firefox">
              <action name="Execute"><execute>firefox</execute></action>
            </item>
            <item label="Terminal">
              <action name="Execute"><execute>xfce4-terminal</execute></action>
            </item>
            <item label="File Manager">
              <action name="Execute"><execute>thunar</execute></action>
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
