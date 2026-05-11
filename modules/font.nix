{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.my.fonts;
in
{
  options.my.fonts = {
    enable = lib.mkEnableOption "shared font management";

    documents  = lib.mkEnableOption "printing & office fonts";
    craft      = lib.mkEnableOption "decorative / Cricut-friendly fonts";
    printing3d = lib.mkEnableOption "3D printing fonts (bold strokes, clean contours)";
    nerd       = lib.mkEnableOption "terminal nerd fonts";

    viewer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install font comparison & inspection tools";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      # Script fonts not yet packaged in nixpkgs — fetch individually from Google Fonts
      great-vibes = pkgs.stdenvNoCC.mkDerivation {
        name = "great-vibes";
        src = pkgs.fetchurl {
          url = "https://github.com/google/fonts/raw/main/ofl/greatvibes/GreatVibes-Regular.ttf";
          sha256 = "059dk3wnfi5kr7q97jpszmdrm3q9x09z7v1i4mbm26vg3019hl4d";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm644 $src $out/share/fonts/truetype/GreatVibes-Regular.ttf
        '';
      };

      allura = pkgs.stdenvNoCC.mkDerivation {
        name = "allura";
        src = pkgs.fetchurl {
          url = "https://github.com/google/fonts/raw/main/ofl/allura/Allura-Regular.ttf";
          sha256 = "1ijcq6x62iiwnbi74ywkpx1ljca0iyhqx2zzqkgw0cjqa4p2n54w";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm644 $src $out/share/fonts/truetype/Allura-Regular.ttf
        '';
      };

      parisienne = pkgs.stdenvNoCC.mkDerivation {
        name = "parisienne";
        src = pkgs.fetchurl {
          url = "https://github.com/google/fonts/raw/main/ofl/parisienne/Parisienne-Regular.ttf";
          sha256 = "0mydmb3lxjn1qp4ydncq1jpl7yjbs5bzbrcp0xqbq81f09zy37mw";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm644 $src $out/share/fonts/truetype/Parisienne-Regular.ttf
        '';
      };

      documentFonts =
        (with pkgs; [
          dejavu_fonts
          noto-fonts
          noto-fonts-cjk-sans
          liberation_ttf
          source-sans
          source-serif
          source-code-pro
          inter
        ])
        ++ (if pkgs ? "noto-fonts-color-emoji" then [ pkgs."noto-fonts-color-emoji" ]
            else if pkgs ? "noto-fonts-emoji" then [ pkgs."noto-fonts-emoji" ]
            else []);

      craftFonts =
        [ great-vibes allura parisienne ]
        ++ (if pkgs ? "eb-garamond" then [ pkgs."eb-garamond" ] else [])
        ++ (if pkgs ? "libre-baskerville" then [ pkgs."libre-baskerville" ] else [])
        ++ (if pkgs ? "oldstandard" then [ pkgs."oldstandard" ] else [])
        ++ (if pkgs ? "junicode" then [ pkgs."junicode" ] else [])
        ++ (if pkgs ? "symbola" then [ pkgs."symbola" ] else []);

      # Fonts optimized for 3D printing: bold strokes, simple contours, reliable extrusion
      printing3dFonts = with pkgs; [
        # Sans-serif (clean, reliable)
        roboto
        lato
        open-sans
        montserrat
        work-sans
        # Bold/display (excellent for signage)
        oswald
        raleway
        # Geometric/industrial
        orbitron
      ];

      # Nerd fonts: nixpkgs naming/packaging has changed over time.
      # We only attempt the classic nerdfonts override when pkgs.nerdfonts exists.
      # Otherwise we fall back to regular JetBrains Mono + Fira Code (non-nerd).
      nerdFonts =
        if pkgs ? nerdfonts then
          [ (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" ]; }) ]
        else
          (with pkgs; [
            jetbrains-mono
            fira-code
          ]);

      selectedFonts = lib.flatten [
        (lib.optionals cfg.documents documentFonts)
        (lib.optionals cfg.craft craftFonts)
        (lib.optionals cfg.printing3d printing3dFonts)
        (lib.optionals cfg.nerd nerdFonts)
      ];
    in
    {
      fonts = {
        packages = selectedFonts;

        fontconfig = {
          enable = true;
          antialias = true;
          hinting.enable = true;

          defaultFonts = {
            serif = [ "Noto Serif" ];
            sansSerif = [ "Noto Sans" ];
            monospace = [ "JetBrains Mono" "Fira Code" ];
          };
        };
      };

      environment.systemPackages = lib.optionals cfg.viewer (with pkgs; [
        font-manager
        gnome-font-viewer
        fontpreview
        fontforge
        imagemagick
        pango
      ]);
    }
  );
}
