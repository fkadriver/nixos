{ config, lib, pkgs, ... }:

let
  # FreeCAD stores config in different locations per platform
  # Linux (XDG): ~/.config/FreeCAD/ and ~/.local/share/FreeCAD/Mod/
  # macOS (Homebrew native app): ~/Library/Preferences/FreeCAD/ and ~/Library/Application Support/FreeCAD/Mod/
  isDarwin = pkgs.stdenv.isDarwin;

  cfgDir = if isDarwin
    then "Library/Preferences/FreeCAD"
    else ".config/FreeCAD";

  modDir = if isDarwin
    then "Library/Application Support/FreeCAD/Mod"
    else ".local/share/FreeCAD/Mod";

  # --- FreeCAD Addon Derivations (none are in nixpkgs) ---

  # A2plus: Assembly constraints workbench
  # https://github.com/kbwbe/A2plus  tag: v0.4.67
  a2plus = pkgs.fetchFromGitHub {
    owner = "kbwbe";
    repo = "A2plus";
    rev = "281693a1901ecbcc6b53e1879bf0b4379e1f32f2";
    sha256 = "0yc0jvrjgsx0xxycwv26yhznc8zpvzm9zav0vpcfhc445n65jb43";
  };

  # CurvesWB: Advanced curve and surface modeling workbench
  # https://github.com/tomate44/CurvesWB  tag: v0.3 + patches
  curvesWB = pkgs.fetchFromGitHub {
    owner = "tomate44";
    repo = "CurvesWB";
    rev = "c1ab555d28f429c000cb5ecdc69a5b0ebdd13d04";
    sha256 = "155rhz89fdxbl71f2fv7nj1dhs31i1hdkrwby4nrrzawnbkk9d5m";
  };

  # Manipulator: Move/rotate/scale objects interactively
  # https://github.com/easyw/Manipulator
  manipulator = pkgs.fetchFromGitHub {
    owner = "easyw";
    repo = "Manipulator";
    rev = "3f6041406bb03a4e4ac6660d03eb0d0805605130";
    sha256 = "08mf3x9ndqmf0ciq585ydzf4bx8vwhfybrv8hpa504kwffhhmsgw";
  };

  # OpenTheme: UI themes (OpenLight, OpenDark, etc.)
  # https://github.com/obelisk79/OpenTheme
  openTheme = pkgs.fetchFromGitHub {
    owner = "obelisk79";
    repo = "OpenTheme";
    rev = "907187b5fc1eb23ff9969a21f54f5166b698665b";
    sha256 = "0ni7zw1qzm0mgfj25d14k1q0kg92lskg1k4911bga28v8dx71lb9";
  };

in {
  # Deploy addons as symlinks from Nix store.
  # Mods are Python code that FreeCAD reads; they don't need to be writable.
  home.file = {
    "${modDir}/A2plus".source = a2plus;
    "${modDir}/Curves".source = curvesWB;
    "${modDir}/Manipulator".source = manipulator;
    "${modDir}/OpenTheme".source = openTheme;
  };

  # Copy user.cfg on first activation only — FreeCAD writes to this file
  # on exit, so it must be mutable. To push a new baseline config, update
  # home-modules/freecad/user.cfg in the repo, delete the live file, and
  # run `home-manager switch` again.
  home.activation.freecadUserConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg_dir="${config.home.homeDirectory}/${cfgDir}"
    cfg="$cfg_dir/user.cfg"
    if [ ! -f "$cfg" ]; then
      $DRY_RUN_CMD mkdir -p "$cfg_dir"
      $DRY_RUN_CMD cp "${./freecad/user.cfg}" "$cfg"
      $DRY_RUN_CMD chmod 644 "$cfg"
    fi
  '';
}
