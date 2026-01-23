{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.solaar.nixosModules.default
  ];

  config = {
    # Enable Solaar service for Logitech device management
    services.solaar = {
      enable = true;
      window = "hide";  # Start hidden in system tray
    };

    # Enable udev rules for Logitech devices
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };
  };
}
