{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.my.printing;

  # Fonts chosen for reliable extrusion / watertight contours in OpenSCAD + PrusaSlicer
  slicerFonts = with pkgs; [
    eb-garamond
    libre-baskerville
    oldstandard
    junicode
    inter
    source-sans
    great-vibes
    allura
    parisienne
  ];

  # Helper: generate a font test plate STL into ~/.cache/font-test-plate/
  # Usage:
  #   generate-font-plate "Your sample text"
  generatePlateScript = pkgs.writeShellScriptBin "generate-font-plate" ''
    set -euo pipefail

    TEXT="$1"
    if [ -z "${TEXT:-}" ]; then
      TEXT="Scott ♥ Steph"
    fi

    WORKDIR="$HOME/.cache/font-test-plate"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    # Build a unique list of installed font families
    fc-list : family | cut -d, -f1 | sort -u > all_fonts.txt

    # Filter to a "known-good for 3D" subset by default. You can tweak this regex.
    REGEX="Garamond|Baskerville|Old Standard|OldStandard|Junicode|Inter|Source Sans|Sans|Great Vibes|Vibes|Allura|Parisienne"

    echo "fonts = [" > fonts.scad
    grep -E "$REGEX" all_fonts.txt | sed 's/"/\\"/g; s/.*/"&",/' >> fonts.scad
    echo "];" >> fonts.scad

    # Escape any double quotes in user text for OpenSCAD
    SAFE_TEXT=$(printf "%s" "$TEXT" | sed 's/"/\\"/g')
    echo "sample_text = \"$SAFE_TEXT\";" >> fonts.scad

    # Plate generator
    cat > font_plate.scad << 'EOF'
include <fonts.scad>

// ----- Plate defaults (Ender-3 class beds) -----
plate_width = 220;
plate_height = 220;
plate_thickness = 2;

// Emboss settings
text_height = 1.2;     // height of raised letters
label_height = 0.6;    // small label height
font_size = 10;
label_size = 5;

// Layout
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
    // Sample text in the target font
    linear_extrude(text_height)
      text(sample_text, size=font_size, font=f, halign="left", valign="baseline");

    // Label (use a stable sans so the font name always renders)
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

    openscad -o font_plate.stl font_plate.scad
    echo "Generated: $WORKDIR/font_plate.stl"
    echo "OpenSCAD sources: $WORKDIR/font_plate.scad and $WORKDIR/fonts.scad"
  '';

  # Helper: generate one keychain STL per font into ~/.cache/font-keychains/
  # Usage:
  #   generate-font-keychains "Your sample text"
  generateKeychainsScript = pkgs.writeShellScriptBin "generate-font-keychains" ''
    set -euo pipefail

    TEXT="$1"
    if [ -z "${TEXT:-}" ]; then
      TEXT="Scott ♥ Steph"
    fi

    WORKDIR="$HOME/.cache/font-keychains"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    fc-list : family | cut -d, -f1 | sort -u > all_fonts.txt
    REGEX="Garamond|Baskerville|Old Standard|OldStandard|Junicode|Inter|Source Sans|Sans|Great Vibes|Vibes|Allura|Parisienne"
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
// Keychain for: $font
// Text is raised (emboss) on a simple rounded tag with a hole.

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
  // base tag
  linear_extrude(tag_t)
    rounded_rect(tag_w, tag_h, corner_r);

  // hole near left side
  translate([8, tag_h/2, -1])
    cylinder(h=tag_t+2, r=hole_r);
}

// embossed text
translate([12, tag_h/2, tag_t])
  linear_extrude(emboss_h)
    text("$SAFE_TEXT", size=9, font="$font", halign="left", valign="center");
EOF

      openscad -o "$stl" "$scad"
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

    # Install fonts chosen for 3D embossing reliability (optional)
    fonts.packages = lib.mkIf cfg.fonts.enable slicerFonts;

    # ONE definition of systemPackages (fixes duplicate definition error)
    environment.systemPackages =
      (with pkgs; [
        openscad
        prusa-slicer
        # orca-slicer
        freecad
        blender
        meshlab
      ])
      ++ lib.optionals cfg.repairTools (with pkgs; [
        inkscape     # text -> path, boolean cleanup
        potrace      # bitmap -> vector cleanup
        fontforge    # inspect glyph topology
        freetype     # font debug tools
      ])
      ++ lib.optionals cfg.generateTestArtifacts [
        generatePlateScript
        generateKeychainsScript
      ];

    # AppImage support (vendor slicers, etc.)
    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    # USB serial access for many printers
    users.groups.dialout = {};
  };
}
