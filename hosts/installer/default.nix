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
        "broadcom-sta-6.30.223.271-59-6.12.68"
      ];

      # Include necessary packages for installation
      environment.systemPackages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
        git
        vim
        tmux
        htop
        parted
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
          echo "Fetching available configurations from $GIT_REPO..."

          # Get list of nixosConfigurations from the flake
          CONFIGS=$(nix --experimental-features "nix-command flakes" flake show --json "$GIT_REPO" 2>/dev/null | \
            jq -r '.nixosConfigurations | keys[]' 2>/dev/null | \
            grep -v "^installer$" | \
            sort)

          if [ -z "$CONFIGS" ]; then
            echo "ERROR: Could not fetch configurations from $GIT_REPO"
            echo "Make sure the repository is accessible and contains nixosConfigurations"
            exit 1
          fi

          echo ""
          echo "Available configurations:"
          i=1
          declare -a config_array
          while IFS= read -r config; do
            config_array[$i]="$config"
            echo "  $i) $config"
            ((i++))
          done <<< "$CONFIGS"

          max_choice=$((i-1))
          echo ""
          read -p "Select configuration (1-$max_choice): " choice

          if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$max_choice" ]; then
            echo "Invalid choice"
            exit 1
          fi

          CONFIG="''${config_array[$choice]}"

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
          echo "Partitioning disk with disko..."
          sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
            --mode disko \
            --flake "$GIT_REPO#$CONFIG" \
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

      # Auto-mount the NIXOS_DATA FAT32 partition if present on the USB drive.
      # This partition is created by scripts/prepare-installer-usb.sh and is
      # used to transfer AGE public keys from newly installed hosts back to the
      # management machine without needing network access.
      systemd.services.mount-usb-data = {
        description = "Mount NIXOS_DATA USB data partition";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" "systemd-udev-settle.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "mount-usb-data" ''
            PART=$(${pkgs.util-linux}/bin/blkid -L NIXOS_DATA 2>/dev/null || true)
            if [ -n "$PART" ]; then
              mkdir -p /mnt/usb-data
              ${pkgs.util-linux}/bin/mount "$PART" /mnt/usb-data
              echo "NIXOS_DATA partition mounted at /mnt/usb-data"
            fi
          '';
        };
      };

      # Add welcome message with instructions
      services.getty.helpLine = ''

        ==========================================
        NixOS Automated Installer
        ==========================================

        To start installation, run:
          /etc/nixos-install-helper.sh

        Manual installation (using git flake directly):
          1. Partition: nix run github:nix-community/disko -- --mode disko --flake <repo>#<config> --arg device '"/dev/sdX"'
          2. Install: nixos-install --flake <repo>#<config>

        The installer will dynamically discover available configurations from your flake.
        WiFi: Pre-configured for JEN_ACRES network

        USB Data Partition (NIXOS_DATA):
          If prepared with scripts/prepare-installer-usb.sh, the data
          partition is mounted at /mnt/usb-data.
          After first boot of a new host, plug in this USB and run:
            sudo mount LABEL=NIXOS_DATA /mnt/usb-data
            sudo age-keygen -y /var/lib/sops-nix/key.txt \
              | sudo tee /mnt/usb-data/$(hostname)-age.pub
            sudo umount /mnt/usb-data

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
