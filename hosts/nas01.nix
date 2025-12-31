{ inputs, ... }@flakeContext:

inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    ./nas01-hardware.nix
    inputs.self.modules.common
    inputs.self.modules.user-scott
    inputs.disko.nixosModules.disko
    inputs.self.modules.disko-config
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
            PasswordAuthentication = true;  # Change to false after setting up keys
          };
        };

        # Open SSH port in firewall
        networking.firewall.allowedTCPPorts = [ 22 ];

        system = {
          stateVersion = "25.04";
        };
      };
    }
  ];
}
