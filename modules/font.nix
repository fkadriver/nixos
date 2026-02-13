{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.my.fonts;

  # Paper / document fonts (laser printing, office, general UI)
  documentFonts = with pkgs; [
    noto-fonts
    noto-fonts-extra
    noto-fonts-cjk-sans
    noto-fonts-emoji

    liberation_ttf
    corefonts
    vistafonts

    source-sans
    source-serif
    source-code-pro
    inter
  ];

  # Decorative / craft fonts (Cricut-friendly bundles)
  craftFonts = with pkgs; [
    google-fonts
    league-of-moveable-type
  ];

  # Nerd fonts (terminal)
  nerdFonts = with pkgs; [
    (nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" ]; })
  ];

  selectedFonts = lib.flatten [
    (lib.optionals cfg.documents documentFonts)
    (lib.optionals cfg.craft craftFonts)
    (lib.optionals cfg.nerd nerdFonts)
  ];
in
{
  options.my.fonts = {
    enable = lib.mkEnableOption "shared font management";

    documents = lib.mkEnableOption "printing & office fonts";
    craft     = lib.mkEnableOption "Cricut / decorative fonts";
    nerd      = lib.mkEnableOption "terminal nerd fonts";

    viewer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install font comparison & inspection tools";
    };
  };

  config = lib.mkIf cfg.enable {

    fonts = {
      packages = selectedFonts;

      fontconfig = {
        enable = true;
        antialias = true;
        hinting.enable = true;

        defaultFonts = {
          serif = [ "Noto Serif" ];
          sansSerif = [ "Noto Sans" ];
          monospace = [ "JetBrainsMono Nerd Font" ];
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
  };
}
