{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Logitech device support using Solaar
    # Solaar is a Linux manager for Logitech Unifying receivers and devices

    # Enable udev rules for Logitech devices
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;  # Enables Solaar GUI
    };

    # Install Solaar package
    environment.systemPackages = with pkgs; [
      solaar  # Logitech device manager
    ];
  };
}
