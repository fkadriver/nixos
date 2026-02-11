{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
  config = {
    # 3D Printing software for Creality Ender 3 V3 KE
    environment.systemPackages = [
      pkgs.openscad           # 3D CAD modeler for creating models
      pkgs.prusa-slicer       # Alternative slicer (PrusaSlicer fork)
#      pkgs.orca-slicer        # Modern slicer with Creality support (recommended)
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
