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

    # Install libinput-gestures for mouse button support
    environment.systemPackages = with pkgs; [
      libinput  # For debugging input devices
      evtest    # For testing input events
      xdotool   # For simulating key presses (X11)
      xbindkeys # For binding mouse buttons to actions
    ];

    # Enable numlockx for Num Lock default on at boot
    services.xserver.displayManager.sessionCommands = ''
      ${pkgs.numlockx}/bin/numlockx on
    '';
  };
}
