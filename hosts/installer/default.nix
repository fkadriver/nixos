{ inputs, ... }@flakeContext:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    inputs.disko.nixosModules.disko
    ({ config, lib, pkgs, ... }: {
      # Include the disko configuration and wireless support
      imports = [
        inputs.self.nixosModules.disko-config
        inputs.self.nixosModules.wireless
      ];

      # ISO-specific configuration
      isoImage.makeEfiBootable = true;
      isoImage.makeUsbBootable = true;

      # Enable experimental features needed for disko and flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # Enable NetworkManager for WiFi connectivity
      networking.networkmanager = {
        enable = true;
        # NetworkManager will use its own wpa_supplicant
        wifi.backend = "wpa_supplicant";
      };

      # Use systemd.network to set the link as WiFi type
      systemd.network.links."10-broadcom-wifi" = {
        matchConfig = {
          Driver = "wl";
        };
        linkConfig = {
          Name = "wlan0";
        };
      };

      # Support for Broadcom WiFi (MacBook Air)
      boot.kernelModules = [ "wl" ];
      boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
      boot.blacklistedKernelModules = [ "b43" "b43legacy" "ssb" "bcm43xx" "brcm80211" "brcmfmac" "brcmsmac" "bcma" ];
      hardware.enableRedistributableFirmware = true;

      # Ensure WiFi is unblocked on boot
      systemd.services.unblock-wifi = {
        description = "Unblock WiFi devices";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.util-linux}/bin/rfkill unblock wifi";
        };
      };

      # Allow unfree broadcom-sta driver
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "broadcom-sta"
      ];
      nixpkgs.config.permittedInsecurePackages = [
        "broadcom-sta-6.30.223.271-59-6.12.60"
        "broadcom-sta-6.30.223.271-59-6.12.63"
      ];

      # Include necessary packages for installation
      environment.systemPackages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
        git
        vim
        tmux
        htop
        parted
        gptfdisk
        lvm2
        curl
        # WiFi utilities
        networkmanager
        util-linux  # includes rfkill
      ];

      # Add installation helper script
      environment.etc."nixos-install-helper.sh" = {
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "=== NixOS Automated Installer ==="
          echo ""
          echo "Git repository URL (e.g., github:username/nixos):"
          read -p "> " GIT_REPO

          echo ""
          echo "Available configurations:"
          echo "  1) latitude-xfce - Dell Latitude 7480 (XFCE)"
          echo "  2) latitude-kde  - Dell Latitude 7480 (KDE Plasma)"
          echo "  3) airbook-kde   - MacBook Air 7,2 (KDE Plasma)"
          echo "  4) nas01         - Server configuration"
          echo ""
          read -p "Select configuration (1-4): " choice

          case $choice in
            1) CONFIG="latitude-xfce" ;;
            2) CONFIG="latitude-kde" ;;
            3) CONFIG="airbook-kde" ;;
            4) CONFIG="nas01" ;;
            *) echo "Invalid choice"; exit 1 ;;
          esac

          echo ""
          echo "Available disks:"
          lsblk -d -o NAME,SIZE,TYPE | grep disk
          echo ""
          read -p "Enter device to install to (e.g., sda, nvme0n1): " DEVICE

          DEVICE="/dev/$DEVICE"

          echo ""
          echo "WARNING: This will ERASE ALL DATA on $DEVICE"
          echo "Git Repository: $GIT_REPO"
          echo "Configuration: $CONFIG"
          read -p "Continue? (yes/no): " confirm

          if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled"
            exit 0
          fi

          echo ""
          echo "Downloading disko configuration..."
          DISKO_URL="https://raw.githubusercontent.com/fkadriver/nixos/main/disko/$CONFIG.nix"
          curl -sL "$DISKO_URL" > /tmp/disko-$CONFIG.nix || {
            echo "ERROR: Failed to download disko configuration from $DISKO_URL"
            exit 1
          }

          echo "Partitioning disk with disko..."
          sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
            --mode destroy,format,mount \
            /tmp/disko-$CONFIG.nix \
            --arg device "\"$DEVICE\""

          echo ""
          echo "Installing NixOS..."
          sudo nixos-install --flake "$GIT_REPO#$CONFIG" --no-root-passwd

          echo ""
          echo "Installation complete!"
          echo "You can now reboot into your new system."
          read -p "Reboot now? (yes/no): " reboot

          if [ "$reboot" == "yes" ]; then
            sudo reboot
          fi
        '';
        mode = "0755";
      };

      # Add welcome message with instructions
      services.getty.helpLine = ''

        ==========================================
        NixOS Automated Installer
        ==========================================

        To start installation, run:
          /etc/nixos-install-helper.sh

        Manual installation (using git flake directly):
          1. Partition: nix run github:nix-community/disko -- --mode disko --flake github:fkadriver/nixos#<config> --arg device '"/dev/sdX"'
          2. Install: nixos-install --flake github:fkadriver/nixos#<config>

        Available configs: latitude-xfce, latitude-kde, airbook-kde, nas01
        WiFi: Pre-configured for JEN_ACRES network

      '';

      # Enable SSH for remote installation
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "yes";
      };

      # Set root password for ISO (change after install)
      # Override the base installer config's initialHashedPassword to eliminate warning
      users.users.root = {
        initialPassword = "nixos";
        initialHashedPassword = lib.mkOverride 50 null;
      };

      networking.hostName = "nixos-installer";
    })
  ];
}
