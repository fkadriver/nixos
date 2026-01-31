{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Printing support with Canon drivers and autodiscovery
    services.printing = {
      enable = true;
      drivers = with pkgs; [
        gutenprint
        gutenprintBin
        cups-filters
        cups-pdf-to-pdf
      ];
      extraConf = ''
        # Enable cups-pdf for printing to PDF
      '';
    };

    # Enable Avahi for printer autodiscovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Configure printers (Canon LBP162)
    # Note: Print-to-PDF functionality available via print dialog in most applications
    # cups-pdf-to-pdf is installed but not configured as a printer queue
    hardware.printers = {
      ensurePrinters = [
        {
          name = "Canon-LBP162";
          location = "Home Office";
          deviceUri = "ipp://LBP162/ipp/print";
          model = "drv:///sample.drv/generic.ppd";
          ppdOptions = {
            PageSize = "Letter";
          };
        }
      ];
      ensureDefaultPrinter = "Canon-LBP162";
    };
  };
}
