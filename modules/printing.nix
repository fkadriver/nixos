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
      ];
    };

    # Enable Avahi for printer autodiscovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Canon LBP162 printer
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
