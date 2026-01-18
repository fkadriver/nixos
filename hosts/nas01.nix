{ inputs, ... }@flakeContext:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    ./nas01-hardware.nix
    ./nas01-disko.nix
    ./nas01-syncthing.nix
    inputs.self.nixosModules.common
    inputs.self.nixosModules.user-scott
    inputs.self.nixosModules.syncthing-declarative
    inputs.self.nixosModules.bitwarden
    inputs.disko.nixosModules.disko
    {
      config = {
        networking = {
          hostName = "nas01";
        };

        # Enable SSH for remote management
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "no";
            PasswordAuthentication = false;  # Use SSH keys only
          };
        };

        # Bitwarden secrets management
        services.bitwarden-secrets = {
          enable = true;
        };

        system = {
          stateVersion = "25.04";
        };
      };
    }
  ];
}
