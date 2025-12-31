{ inputs, ... }@flakeContext:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    inputs.disko.nixosModules.disko
    {
      # Include the disko configuration
      imports = [ inputs.self.modules.disko-config ];

      # ISO-specific configuration
      isoImage.makeEfiBootable = true;
      isoImage.makeUsbBootable = true;

      # Include necessary packages for installation
      environment.systemPackages = with inputs.nixpkgs.legacyPackages.x86_64-linux; [
        git
        vim
        tmux
        htop
        parted
        gptfdisk
        lvm2
      ];

      # Add installation helper script
      environment.etc."nixos-install-helper.sh" = {
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "=== NixOS Automated Installer ==="
          echo ""
          echo "Available configurations:"
          echo "  1) latitude - Dell Latitude 7480"
          echo "  2) airbook  - MacBook Air 7,2"
          echo "  3) nas01    - Server configuration"
          echo ""
          read -p "Select configuration (1-3): " choice

          case $choice in
            1) CONFIG="latitude" ;;
            2) CONFIG="airbook" ;;
            3) CONFIG="nas01" ;;
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
          echo "Configuration: $CONFIG"
          read -p "Continue? (yes/no): " confirm

          if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled"
            exit 0
          fi

          echo ""
          echo "Partitioning disk with disko..."
          sudo nix run github:nix-community/disko -- --mode disko \
            --flake /etc/nixos#$CONFIG \
            --arg device "\"$DEVICE\""

          echo ""
          echo "Cloning configuration repository..."
          sudo git clone https://github.com/YOUR_USERNAME/nixos /mnt/etc/nixos

          echo ""
          echo "Installing NixOS..."
          sudo nixos-install --flake /mnt/etc/nixos#$CONFIG

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
          nixos-install-helper.sh

        Manual installation steps:
          1. Partition disk: disko --mode disko --flake .#<config> --arg device '"/dev/sdX"'
          2. Clone config: git clone <repo> /mnt/etc/nixos
          3. Install: nixos-install --flake /mnt/etc/nixos#<config>

        Available configs: latitude, airbook, nas01

      '';

      # Enable SSH for remote installation
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "yes";
      };

      # Set root password for ISO (change after install)
      users.users.root.password = "nixos";

      networking.hostName = "nixos-installer";
    }
  ];
}
