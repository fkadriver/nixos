{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.my.printing;

  # FreeCAD 1.1.0 is available in nixpkgs 25.11 but not yet in nixpkgs-unstable
  pkgs2511 = inputs.nixpkgs-2511.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  freecad = pkgs2511.freecad;

  # Some font package names can vary across nixpkgs revisions. Only include those that exist.
  fontPkgs =
    (if pkgs ? "eb-garamond" then [ pkgs."eb-garamond" ] else []) ++
    (if pkgs ? "libre-baskerville" then [ pkgs."libre-baskerville" ] else []) ++
    (if pkgs ? "oldstandard" then [ pkgs."oldstandard" ] else []) ++
    (if pkgs ? "junicode" then [ pkgs."junicode" ] else []) ++
    (if pkgs ? "inter" then [ pkgs."inter" ] else []) ++
    (if pkgs ? "source-sans" then [ pkgs."source-sans" ] else []);

  # Single directory of symlinks for FreeCAD Draft→ShapeString font browsing.
  freecadFontDir = pkgs.runCommand "freecad-print-fonts" {} ''
    mkdir -p "$out"
    for pkg in ${lib.concatStringsSep " " fontPkgs}; do
      if [ -d "$pkg/share/fonts" ]; then
        find "$pkg/share/fonts" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec ln -s {} "$out" \;
      fi
    done
  '';

  bosl2 = pkgs.fetchFromGitHub {
    owner = "BelfrySCAD";
    repo = "BOSL2";
    rev = "881947c32a28fa68049b518dcc1e73202bfc2c7c";
    hash = "sha256-0qy9WX7lhiVoY5Jv5pdXHOMXf6QfnrEJ5XHzv5B2Skk=";
  };

  generatePlateScript = pkgs.writeShellScriptBin "generate-font-plate" ''
    set -euo pipefail

    TEXT="$1"
    if [ -z "$TEXT" ]; then
      TEXT="Scott ♥ Steph"
    fi  

    WORKDIR="$HOME/.cache/font-test-plate"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    # Build a unique list of installed font families
    ${pkgs.fontconfig}/bin/fc-list : family | cut -d, -f1 | sort -u > all_fonts.txt

    # Filter to a "known-good for 3D" subset by default. You can tweak this regex.
    REGEX="Roboto|Lato|Open Sans|Montserrat|Work Sans|Oswald|Archivo|Raleway|Orbitron|Garamond|Baskerville|Old Standard|OldStandard|Junicode|Inter|Source Sans|Noto Sans|DejaVu"

    echo "fonts = [" > fonts.scad
    grep -E "$REGEX" all_fonts.txt | sed 's/"/\\"/g; s/.*/"&",/' >> fonts.scad || true
    echo "];" >> fonts.scad

    # Escape any double quotes in user text for OpenSCAD
    SAFE_TEXT=$(printf "%s" "$TEXT" | sed 's/"/\\"/g')
    echo "sample_text = \"$SAFE_TEXT\";" >> fonts.scad

    cat > font_plate.scad << 'EOF'
include <fonts.scad>

plate_width = 220;
plate_height = 220;
plate_thickness = 2;

text_height = 1.2;
label_height = 0.6;
font_size = 10;
label_size = 5;

cols = 2;
rows = ceil(len(fonts) / cols);

cell_w = plate_width / cols;
cell_h = plate_height / rows;

padding = 6;

module base_plate() {
  cube([plate_width, plate_height, plate_thickness], center=false);
}

module font_cell(f, idx) {
  col = idx % cols;
  row = floor(idx / cols);

  x = col * cell_w;
  y = plate_height - (row+1)*cell_h;

  translate([x + padding, y + padding, plate_thickness]) {
    linear_extrude(text_height)
      text(sample_text, size=font_size, font=f, halign="left", valign="baseline");

    translate([0, font_size + 3, 0])
      linear_extrude(label_height)
        text(f, size=label_size, font="Noto Sans", halign="left", valign="baseline");
  }
}

union() {
  base_plate();
  for (i = [0 : len(fonts)-1]) font_cell(fonts[i], i);
}
EOF

    ${pkgs.openscad-unstable}/bin/openscad -o font_plate.stl font_plate.scad
    echo "Generated: $WORKDIR/font_plate.stl"
  '';

  generateKeychainsScript = pkgs.writeShellScriptBin "generate-font-keychains" ''
    set -euo pipefail

    TEXT="$1"
    if [ -z "$TEXT" ]; then
      TEXT="Scott ♥ Steph"
    fi

    WORKDIR="$HOME/.cache/font-keychains"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    ${pkgs.fontconfig}/bin/fc-list : family | cut -d, -f1 | sort -u > all_fonts.txt
    REGEX="Roboto|Lato|Open Sans|Montserrat|Work Sans|Oswald|Archivo|Raleway|Orbitron|Garamond|Baskerville|Old Standard|OldStandard|Junicode|Inter|Source Sans|Noto Sans|DejaVu"
    grep -E "$REGEX" all_fonts.txt > fonts.txt || true

    if [ ! -s fonts.txt ]; then
      echo "No fonts matched REGEX. Edit REGEX in the script or install fonts, then retry."
      exit 1
    fi

    SAFE_TEXT=$(printf "%s" "$TEXT" | sed 's/"/\\"/g')

    i=0
    while IFS= read -r font; do
      safe_font=$(printf "%s" "$font" | tr ' /' '__' | tr -cd '[:alnum:]_-.')
      scad=$(printf "keychain_%03d_%s.scad" "$i" "$safe_font")
      stl=$(printf "keychain_%03d_%s.stl" "$i" "$safe_font")

      cat > "$scad" << EOF
tag_w = 70;
tag_h = 22;
tag_t = 2.4;

emboss_h = 1.2;
hole_r = 2.4;
corner_r = 3;

module rounded_rect(w,h,r) {
  hull() {
    translate([r, r, 0]) cylinder(h=0.01, r=r);
    translate([w-r, r, 0]) cylinder(h=0.01, r=r);
    translate([r, h-r, 0]) cylinder(h=0.01, r=r);
    translate([w-r, h-r, 0]) cylinder(h=0.01, r=r);
  }
}

difference() {
  linear_extrude(tag_t)
    rounded_rect(tag_w, tag_h, corner_r);

  translate([8, tag_h/2, -1])
    cylinder(h=tag_t+2, r=hole_r);
}

translate([12, tag_h/2, tag_t])
  linear_extrude(emboss_h)
    text("$SAFE_TEXT", size=9, font="$font", halign="left", valign="center");
EOF

      ${pkgs.openscad-unstable}/bin/openscad -o "$stl" "$scad"
      i=$((i+1))
    done < fonts.txt

    echo "Generated $i keychains in $WORKDIR"
  '';
in
{
  options.my.printing = {
    enable = lib.mkEnableOption "3D printing tools";

    fonts.enable = lib.mkEnableOption "Install slicer-safe emboss fonts";

    repairTools = lib.mkEnableOption "SVG/STL repair & text preparation tools";

    generateTestArtifacts = lib.mkEnableOption ''
      Install generators for 3D-print font test artifacts:
      - generate-font-plate: one big multi-font emboss plate (STL)
      - generate-font-keychains: one keychain STL per font
    '';
  };

  config = lib.mkIf cfg.enable {

    # Core modeling / slicing
    environment.systemPackages =
      [ freecad ] ++  # FreeCAD 1.1.0 from nixpkgs 25.11
      (with pkgs; [
        openscad-unstable
        orca-slicer
        prusa-slicer
        blender
        meshlab
        sweethome3d.application
        solvespace
        f3d
      ])
      ++ lib.optionals cfg.repairTools (with pkgs; [
        inkscape
        potrace
        fontforge
        freetype
      ])
      ++ lib.optionals cfg.generateTestArtifacts [
        generatePlateScript
        generateKeychainsScript
      ];

    fonts.packages = lib.mkIf cfg.fonts.enable fontPkgs;

    # Stable path for FreeCAD Draft→ShapeString font browsing
    environment.etc."freecad/fonts".source = lib.mkIf cfg.fonts.enable freecadFontDir;

    # Install BOSL2 library to OpenSCAD user libraries directory
    system.activationScripts.openscadBosl2 = {
      text = ''
        OPENSCAD_LIB="/home/scott/.local/share/OpenSCAD/libraries"
        mkdir -p "$OPENSCAD_LIB"
        if [ ! -L "$OPENSCAD_LIB/BOSL2" ]; then
          rm -rf "$OPENSCAD_LIB/BOSL2"
          ln -sfn ${bosl2} "$OPENSCAD_LIB/BOSL2"
          chown -h scott:users "$OPENSCAD_LIB/BOSL2" 2>/dev/null || true
        fi
      '';
    };

    # Symlink orca-settings repo as OrcaSlicer user config (runs after each rebuild).
    # No-op if the repo hasn't been cloned yet.
    system.activationScripts.orcaSettings = {
      text = ''
        REPO="/home/scott/git/orca-settings"
        ORCA_DIR="/home/scott/.config/OrcaSlicer"
        if [ -d "$REPO" ]; then
          mkdir -p "$ORCA_DIR"
          if [ ! -L "$ORCA_DIR/user" ]; then
            rm -rf "$ORCA_DIR/user"
            ln -sfn "$REPO" "$ORCA_DIR/user"
            chown -h scott:users "$ORCA_DIR/user" 2>/dev/null || true
          fi
        fi
      '';
    };

    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    users.groups.dialout = {};
  };
}
