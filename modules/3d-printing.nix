{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # 3D Printing software for Creality Ender 3 V3 KE
    # Based on: https://gist.github.com/Force67/d9bb6acb37d9febf8554fa87dc916afe

    # UltiMaker Cura - Best slicer for Ender 3 V3 KE
    # Using AppImage for latest version with desktop integration
    environment.systemPackages = [
      # Cura AppImage wrapper
      (pkgs.appimageTools.wrapType2 {
        pname = "cura5";
        name = "cura5";
        version = "5.7.1";
        src = pkgs.fetchurl {
          url = "https://github.com/Ultimaker/Cura/releases/download/5.7.1/UltiMaker-Cura-5.7.1-linux-X64.AppImage";
          sha256 = "2d9303d1fa3c4d2943109b29bd391aef6e2562ae4482b3a50e4c0c92d5ea013c";
        };
        extraPkgs = pkgs: with pkgs; [ ];
      })

      # Additional 3D printing tools
      pkgs.openscad           # 3D CAD modeler for creating models
      pkgs.prusa-slicer       # Alternative slicer (PrusaSlicer fork)
      pkgs.freecad            # Parametric 3D CAD modeler
      pkgs.blender            # 3D creation suite (modeling, animation, rendering)
      pkgs.meshlab            # System for processing 3D meshes
    ];

    # Desktop entry for Cura with proper file handling
    environment.etc."xdg/cura.desktop" = {
      text = ''
        [Desktop Entry]
        Version=1.0
        Name=UltiMaker Cura
        Comment=3D Printing Slicer for Creality Ender 3 V3 KE
        Exec=cura5 %f
        Icon=cura-icon
        Terminal=false
        Type=Application
        Categories=Graphics;3DGraphics;Engineering;
        MimeType=model/stl;application/x-stl;model/x.stl-binary;model/x.stl-ascii;application/sla;
        Keywords=3D;printing;slicer;STL;gcode;
      '';
      mode = "0644";
    };

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
