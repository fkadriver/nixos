{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  # Sweet Home 3D plugins
  # Note: Plugins must be manually downloaded and placed in ~/.local/share/Sweet Home 3D/plugins/
  # This creates a helper script to manage plugin installation

  # Create a script to help users install plugins
  installPluginsScript = pkgs.writeShellScriptBin "sweethome3d-install-plugins" ''
    set -e

    PLUGINS_DIR="$HOME/.local/share/Sweet Home 3D/plugins"
    DOWNLOADS_DIR="$HOME/Downloads/sweethome3d-plugins"

    mkdir -p "$PLUGINS_DIR"
    mkdir -p "$DOWNLOADS_DIR"

    echo "Sweet Home 3D Plugin Installer"
    echo "==============================="
    echo ""
    echo "Plugin directory: $PLUGINS_DIR"
    echo ""

    # List of plugins to download
    cat <<EOF
Please download the following plugins manually and place them in:
$DOWNLOADS_DIR

Required plugins:
1. StaircaseGenerator-1.0.1.sh3p (150 KB)
   - Creates 3D staircases from parameters
   - Download from: https://www.sweethome3d.com/plugins.jsp

2. TerrainGenerator-1.2.2.sh3p (111 KB)
   - Creates terrain from room surfaces
   - Download from: https://www.sweethome3d.com/plugins.jsp

3. AutoDimensioning.sh3p (44 KB)
   - Automatic dimension annotation
   - Download from: https://www.sweethome3d.com/plugins.jsp

4. 3D Models Contributions
   - Additional 3D furniture models
   - Download from: https://www.sweethome3d.com/importModels.jsp
   - Look for contribution libraries in .sh3f format

Once downloaded, this script will install them to:
$PLUGINS_DIR

EOF

    # Check if any plugin files exist in downloads directory
    if ls "$DOWNLOADS_DIR"/*.sh3p >/dev/null 2>&1 || ls "$DOWNLOADS_DIR"/*.sh3f >/dev/null 2>&1; then
      echo "Found plugin files in $DOWNLOADS_DIR"
      echo "Installing plugins..."
      cp -v "$DOWNLOADS_DIR"/*.sh3p "$PLUGINS_DIR/" 2>/dev/null || true
      cp -v "$DOWNLOADS_DIR"/*.sh3f "$PLUGINS_DIR/" 2>/dev/null || true
      echo ""
      echo "Plugins installed! Restart Sweet Home 3D to use them."
    else
      echo "No plugin files found in $DOWNLOADS_DIR yet."
      echo "Download the plugins above and run this script again."
    fi

    echo ""
    echo "To download plugins, visit:"
    echo "  https://www.sweethome3d.com/plugins.jsp"
    echo "  https://www.sweethome3d.com/importModels.jsp"
  '';
in
{
  config = {
    # Home design and remodeling software for deck planning and home projects

    environment.systemPackages = with pkgs; [
      # Sweet Home 3D - Interior design application
      # Great for floor plans, deck layouts, and home remodeling visualization
      sweethome3d.application

      # Sweet Home 3D plugin installer helper
      installPluginsScript

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

    # Sweet Home 3D Plugins Installation:
    # =====================================
    # Plugins must be manually downloaded due to licensing/distribution restrictions.
    #
    # To install plugins:
    # 1. Run: sweethome3d-install-plugins
    # 2. Follow the instructions to download plugins
    # 3. Run the command again to install them
    #
    # Recommended plugins:
    # - StaircaseGenerator-1.0.1.sh3p - Create custom staircases
    # - TerrainGenerator-1.2.2.sh3p - Generate terrain and landscapes
    # - AutoDimensioning.sh3p - Automatic dimension annotations
    # - 3D Models Contributions - Additional furniture libraries
    #
    # Plugin locations:
    # - Plugins (.sh3p): ~/.local/share/Sweet Home 3D/plugins/
    # - Furniture (.sh3f): ~/.local/share/Sweet Home 3D/furniture/
    # - Downloaded plugins: ~/Downloads/sweethome3d-plugins/

    # LibreCAD configuration
    # Patterns and templates stored in: ~/.local/share/LibreCAD/
  };
}
