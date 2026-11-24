{ inputs, ... }@flakeContext:
# MacBook Air 7,2 back on NixOS (XFCE), restored 2026-11-20 from
# archive/hosts/airbook after a forced macOS Tahoe upgrade. The nix-darwin
# config (hosts/airbook-darwin) is kept alongside in case it goes back.
# Shared config is in ./base.nix; ./kde.nix is the Plasma variant.
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    ./base.nix
    ./desktop.nix  # Plank dock + default apps (XFCE-specific)
    inputs.self.nixosModules.laptop-xfce
  ];
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
}
