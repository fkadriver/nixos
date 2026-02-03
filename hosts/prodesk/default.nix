{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.desktop-minimal
      inputs.self.nixosModules.user-scott
    ];

    config = {
      networking = {
        hostName = "prodesk";
      };

      # NOTE: Bitwarden secrets are configured in desktop-minimal module
      # After first boot, get the AGE key for SOPS:
      #   sudo age-keygen -y /var/lib/sops-nix/key.txt
      # Then add this key to .sops.yaml to enable secret management

      # Optional: Enable Borg backup to nas01
      # Uncomment and configure if you want backups
      # services.borg-backup = {
      #   enable = true;
      #   repository = "ssh://scott@nas01.warthog-royal.ts.net/mnt/wd18T/Backups/prodesk";
      #   encryption.passphraseFile = "/etc/borg-passphrase";
      #   sshKeyFile = "/home/scott/.ssh/id_ed25519";
      # };

      # Enable NVIDIA drivers if present (uncomment if you have NVIDIA GPU)
      # hardware.opengl = {
      #   enable = true;
      #   driSupport = true;
      #   driSupport32Bit = true;
      # };
      # services.xserver.videoDrivers = [ "nvidia" ];
      # hardware.nvidia = {
      #   modesetting.enable = true;
      #   powerManagement.enable = false;
      #   powerManagement.finegrained = false;
      #   open = false;  # Use proprietary driver
      #   nvidiaSettings = true;
      #   package = config.boot.kernelPackages.nvidiaPackages.stable;
      # };

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
