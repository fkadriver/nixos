{ inputs, ... }@flakeContext:
# airbook-kde: the same airbook config with Plasma 6 (Wayland, SDDM) in
# place of XFCE, the laptop-kde module latitude uses. Added 2026-11-23 to try
# KDE on the MacBook Air (8 GB RAM). Not included: ./desktop.nix (Plank and
# XFCE app helpers), since Plasma has its own task manager and default apps.
#
# Switching between variants is a normal rebuild, and both keep hostName
# "airbook". Each one's generations are labelled in the boot menu ("XFCE" /
# "KDE"), so you can go back by picking an XFCE entry at boot.
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    ./base.nix
    inputs.self.nixosModules.laptop-kde
  ];
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
}
