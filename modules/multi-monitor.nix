{ inputs, ... }@flakeContext:
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

  # Laptop docking configuration with custom lid switch handler
  services.logind.settings.Login = {
    # Let our custom script handle lid events when docked/on external power
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";

    # When undocked and on battery, suspend immediately
    HandleLidSwitch = lib.mkDefault "suspend";
  };

  # Custom lid switch handler script
  environment.etc."lid-switch-handler.sh" = {
    text = ''
      #!${pkgs.bash}/bin/bash
      # Custom lid switch handler for docked/external power scenarios

      # Set PATH for NixOS
      PATH=/run/current-system/sw/bin:$PATH

      # Find the X display and user
      for x in /tmp/.X11-unix/X*; do
        DISPLAY=":''${x##/tmp/.X11-unix/X}"
        USER=$(who | grep "(:''${x##/tmp/.X11-unix/X})" | awk '{print $1}' | head -1)
        if [ -n "$USER" ]; then
          break
        fi
      done

      # If no X session found, log and exit
      if [ -z "$DISPLAY" ] || [ -z "$USER" ]; then
        logger "Lid event: No X session found, skipping"
        exit 0
      fi

      export DISPLAY
      export XAUTHORITY="/home/$USER/.Xauthority"

      LID_STATE=$(cat /proc/acpi/button/lid/LID*/state | awk '{print $2}')

      if [ "$LID_STATE" = "closed" ]; then
        # Check if we have external displays connected
        EXTERNAL_DISPLAYS=$(su - "$USER" -c "DISPLAY=$DISPLAY xrandr | grep ' connected' | grep -v 'eDP' | wc -l")

        if [ "$EXTERNAL_DISPLAYS" -gt 0 ]; then
          # Disable the laptop's internal display
          INTERNAL_DISPLAY=$(su - "$USER" -c "DISPLAY=$DISPLAY xrandr | grep 'eDP' | awk '{print \$1}'")
          if [ -n "$INTERNAL_DISPLAY" ]; then
            su - "$USER" -c "DISPLAY=$DISPLAY xrandr --output $INTERNAL_DISPLAY --off"
            logger "Lid closed: Disabled internal display $INTERNAL_DISPLAY"
          fi
        else
          # No external displays - start 5-minute suspend countdown
          logger "Lid closed: No external displays, starting 5-minute suspend countdown"
          systemd-run --on-active=5m --timer-property=AccuracySec=1s \
            /run/current-system/sw/bin/systemctl suspend

          # Notify user about the countdown
          su - "$USER" -c "DISPLAY=$DISPLAY notify-send -u critical 'Lid Closed' \
            'No external displays detected. System will suspend in 5 minutes.' \
            -t 10000"
        fi
      else
        # Lid opened - cancel any pending suspend and restore display configuration
        pkill -f "systemd-run.*suspend" && \
          logger "Lid opened: Cancelled suspend timer"

        # Use autorandr to restore the proper multi-monitor configuration
        # This handles positioning correctly (extends instead of mirroring)
        if command -v autorandr >/dev/null 2>&1; then
          su - "$USER" -c "DISPLAY=$DISPLAY autorandr --change"
          logger "Lid opened: Restored display configuration with autorandr"
        else
          # Fallback: just enable the internal display
          INTERNAL_DISPLAY=$(su - "$USER" -c "DISPLAY=$DISPLAY xrandr | grep 'eDP' | awk '{print \$1}'")
          if [ -n "$INTERNAL_DISPLAY" ]; then
            su - "$USER" -c "DISPLAY=$DISPLAY xrandr --output $INTERNAL_DISPLAY --auto"
            logger "Lid opened: Enabled internal display $INTERNAL_DISPLAY (autorandr not available)"
          fi
        fi
      fi
    '';
    mode = "0755";
  };

  # ACPI event handler for lid switch
  services.acpid = {
    enable = true;
    lidEventCommands = ''
      # Only run custom handler when on external power or docked
      # Check both AC* (Dell) and ADP* (MacBook) power supply paths
      POWER_STATE=$(cat /sys/class/power_supply/AC*/online 2>/dev/null || cat /sys/class/power_supply/ADP*/online 2>/dev/null || echo "0")

      if [ "$POWER_STATE" = "1" ]; then
        # On external power - use custom handler
        /etc/lid-switch-handler.sh
      fi
      # When on battery, logind will handle it (immediate suspend)
    '';
  };

  # Enable power management for laptops
  services.upower.enable = true;

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
