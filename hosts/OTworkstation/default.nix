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

      # xrdp remote desktop — XFCE session, accessible on all interfaces (opens port 3389)
      services.xrdp = {
        enable = true;
        defaultWindowManager = "startxfce4";
        openFirewall = true;
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
