{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
  {
  config = {
    # 3D Printing software for Creality Ender 3 V3 KE
    environment.systemPackages = with pkgs; [
      openscad           # 3D CAD modeler for creating models
      prusa-slicer       # Alternative slicer (PrusaSlicer fork)
#      pkgs.orca-slicer        # Modern slicer with Creality support (recommended)
      freecad            # Parametric 3D CAD modeler
      blender            # 3D creation suite (modeling, animation, rendering)
      meshlab            # System for processing 3D meshes
      # Fonts chosen for reliable extrusion / watertight contours in OpenSCAD + PrusaSlicer
    eb-garamond
    libre-baskerville
    oldstandard
    junicode
    inter
    source-sans
    # great-vibes
    # allura
    # parisienne
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
