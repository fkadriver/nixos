{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Home design and remodeling software for deck planning and home projects

    environment.systemPackages = with pkgs; [
      # Sweet Home 3D - Interior design application
      # Great for floor plans, deck layouts, and home remodeling visualization
      sweethome3d.application

      # Alternative/Complementary tools
      librecad              # 2D CAD for precise measurements and technical drawings
      qcad                  # Professional 2D CAD (more features than LibreCAD)
      freecad               # 3D parametric CAD (also useful for 3D printing)

      # FreeCAD is excellent for deck design because:
      # - Parametric design (easy to adjust dimensions)
      # - BOM (Bill of Materials) generation
      # - Structural analysis capabilities
      # - Export to various formats

      # Blender (if not already installed via 3d-printing module)
      # Can be used for photorealistic renders of your deck design
      blender
    ];

    # Sweet Home 3D additional furniture libraries location
    # User can download additional furniture from:
    # http://www.sweethome3d.com/download.jsp
    # Files should be placed in: ~/.local/share/Sweet Home 3D/

    # LibreCAD configuration
    # Patterns and templates stored in: ~/.local/share/LibreCAD/
  };
}
