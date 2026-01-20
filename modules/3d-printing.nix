{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  # Cura AppImage wrapper
  cura5 = pkgs.appimageTools.wrapType2 {
    pname = "cura5";
    name = "cura5";
    version = "5.7.1";
    src = pkgs.fetchurl {
      url = "https://github.com/Ultimaker/Cura/releases/download/5.7.1/UltiMaker-Cura-5.7.1-linux-X64.AppImage";
      sha256 = "2d9303d1fa3c4d2943109b29bd391aef6e2562ae4482b3a50e4c0c92d5ea013c";
    };
    extraPkgs = pkgs: with pkgs; [ ];
  };

  # Desktop entry for Cura
  curaDesktopItem = pkgs.makeDesktopItem {
    name = "cura5";
    desktopName = "UltiMaker Cura";
    comment = "3D Printing Slicer for Creality Ender 3 V3 KE";
    exec = "${cura5}/bin/cura5 %f";
    icon = "cura-icon";
    terminal = false;
    categories = [ "Graphics" "3DGraphics" "Engineering" ];
    mimeTypes = [ "model/stl" "application/x-stl" "model/x.stl-binary" "model/x.stl-ascii" "application/sla" ];
    keywords = [ "3D" "printing" "slicer" "STL" "gcode" ];
  };
in
{
  config = {
    # 3D Printing software for Creality Ender 3 V3 KE
    environment.systemPackages = [
      cura5
      curaDesktopItem

      # Additional 3D printing tools
      pkgs.openscad           # 3D CAD modeler for creating models
      pkgs.prusa-slicer       # Alternative slicer (PrusaSlicer fork)
      pkgs.freecad            # Parametric 3D CAD modeler
      pkgs.blender            # 3D creation suite (modeling, animation, rendering)
      pkgs.meshlab            # System for processing 3D meshes
    ];

    # Enable AppImage support
    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    # Serial port access for 3D printer connection
    # Add your user to dialout group for USB serial access
    users.groups.dialout = {};
  };
}
