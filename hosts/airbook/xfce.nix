{ inputs, ... }@flakeContext:
# airbook-xfce: the airbook config with XFCE and the Plank dock instead of
# Plasma (the default until 2026-11-26; see ./default.nix). Lighter on the
# 8 GB MacBook Air. Shared config is in ./base.nix.
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    ./base.nix
    ./desktop.nix  # Plank dock + default apps (XFCE-specific)
    inputs.self.nixosModules.laptop-xfce
  ];
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
}
