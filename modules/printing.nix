{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  # Driverless (IPP Everywhere / AirPrint) PPD for the LBP162, generated once
  # from the printer's own attributes with cups-filters' `driverless cat
  # driverless:ipp://LBP162.local:631/ipp/print`. Committed rather than using
  # `model = "everywhere"`, because that makes lpadmin query the printer at
  # every CUPS start: with the printer off, cups.service's post-start fails
  # and CUPS restart-loops (seen 2026-11-17). Regenerate after a firmware
  # update if the printer's capabilities change.
  lbp162Ppd = pkgs.runCommand "canon-lbp162-ppd" { } ''
    install -Dm644 ${./printing-canon-lbp162.ppd} $out/share/cups/model/canon-lbp162-driverless.ppd
  '';
in {
  config = {
    # Printing with autodiscovery. The LBP162 is driven driverlessly (PWG
    # raster/URF via the PPD above), so no vendor driver package is needed.
    services.printing = {
      enable = true;
      drivers = [ pkgs.cups-filters lbp162Ppd ];
      # No cups-browsed: it auto-created a second queue for the same printer
      # (Canon_LBP161_LBP162, implicitclass) next to the declared one below.
      # The LBP162 is the only printer, so network auto-queues add nothing.
      browsed.enable = false;
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
          # .local (mDNS via avahi below): the bare name LBP162 doesn't
          # resolve on this network.
          deviceUri = "ipp://LBP162.local:631/ipp/print";
          # The printer speaks AirPrint (pwg-raster/URF) but not PostScript,
          # so the old generic PostScript PPD was a mismatch.
          model = "canon-lbp162-driverless.ppd";
          ppdOptions = {
            PageSize = "Letter";
          };
        }
      ];
      ensureDefaultPrinter = "Canon-LBP162";
    };
  };
}
