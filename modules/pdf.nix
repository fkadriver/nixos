{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    poppler-utils  # pdftotext, pdfinfo, pdfimages, etc.
    pdfarranger    # GUI for merging, reordering, and splitting PDFs
  ];
}
