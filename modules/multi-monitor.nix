{ config, lib, pkgs, ... }: {
  # Multi-monitor support with autorandr for automatic profile switching

  services.autorandr = {
    enable = true;
    # Automatically detect and switch profiles when monitors change
  };

  # Install display configuration tools
  environment.systemPackages = with pkgs; [
    arandr          # GUI for configuring displays (generates xrandr commands)
    autorandr       # Automatic display configuration
    xorg.xrandr     # CLI display configuration
  ];

  # Laptop docking configuration
  services.logind = {
    # Don't suspend when lid is closed while docked
    lidSwitchDocked = "ignore";

    # When undocked, you can set this to "suspend" or "ignore"
    # "ignore" is useful if you want to use the laptop closed with external monitor
    lidSwitch = lib.mkDefault "suspend";

    # Don't suspend when docked with external displays
    lidSwitchExternalPower = lib.mkDefault "ignore";
  };

  # Enable power management for laptops
  services.upower.enable = true;
  services.acpid.enable = true;

  powerManagement = {
    enable = true;
  };

  # TLP for better battery life and docking station support
  services.tlp = {
    enable = true;
    settings = {
      # Disable USB auto-suspend to prevent issues with docking stations
      USB_AUTOSUSPEND = 0;

      # Keep USB devices active when docked
      USB_EXCLUDE_BTUSB = 1;
      USB_EXCLUDE_PHONE = 1;
      USB_EXCLUDE_PRINTER = 1;
      USB_EXCLUDE_WWAN = 1;
    };
  };
}
