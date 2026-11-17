{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Printing with autodiscovery. The LBP162 uses CUPS's built-in generic
    # PostScript PPD below, so no vendor driver package is needed.
    services.printing = {
      enable = true;
      drivers = [ pkgs.cups-filters ];
    };

    # Enable Avahi for printer autodiscovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Configure printers (Canon LBP162)
    # Print-to-PDF comes from the applications' own print dialogs.
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
