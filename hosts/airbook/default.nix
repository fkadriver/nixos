{ inputs, ... }@flakeContext:
# MacBook Air 7,2 on NixOS (restored 2026-11-20 from archive/hosts/airbook
# after a forced macOS Tahoe upgrade; the nix-darwin airbook-darwin config
# was deleted on 2026-11-26, last present in commit 2ef6a2e).
#
# Default: Plasma 6 (Wayland, SDDM) via laptop-kde, as on latitude. Tried as
# airbook-kde from 2026-11-23 and made the default 2026-11-26 (the lag on 8 GB
# RAM is acceptable). ./xfce.nix is the XFCE + Plank variant (airbook-xfce);
# shared config is in ./base.nix.
#
# Both variants keep hostName "airbook" and label their boot entries ("KDE" /
# "XFCE"), so you can go back by picking an XFCE entry at boot.
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    ./base.nix
    inputs.self.nixosModules.laptop-kde
  ];
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
}
