{ inputs, ... }@flakeContext:
let
  nixosModule = { config, lib, pkgs, ... }: {
    imports = [
      ./hardware.nix
      inputs.self.nixosModules.common
      inputs.self.nixosModules.bitwarden
      inputs.self.nixosModules.bitwarden-scott
      inputs.self.nixosModules.wazuh-agent
      inputs.self.nixosModules.laptop-minimal
      inputs.self.nixosModules.user-scott
      inputs.self.nixosModules.fwupd
    ];
    config = {
      # Filesystems come from ./hardware.nix (its diskoLayout switch).

      hardware.logitech.wireless.enable = true;
      programs.solaar.enable = true;
      networking = {
        hostName = "latitude-nixos";
      };

      services.wazuh-agent = {
        enable = true;
        manager = "wazuh.warthog-royal.ts.net";
        enrollmentPasswordFile = "/run/bitwarden-secrets/wazuh_agent_enrollment_password";
      };
      system = {
        stateVersion = "25.04";
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
