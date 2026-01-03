{ config, lib, pkgs, ... }: {
  # Autorandr profiles for automatic display configuration
  # To get monitor fingerprints, run: autorandr --fingerprint
  #
  # Usage:
  # 1. Connect your monitors in each configuration (docked/undocked)
  # 2. Run: autorandr --fingerprint
  # 3. Copy the output and update the fingerprints below
  # 4. Manually configure displays using arandr or XFCE display settings
  # 5. Save the profile: autorandr --save profile-name
  # 6. Update this config with the saved profile
  #
  # Autorandr will automatically switch profiles when monitors are connected/disconnected

  # Example configuration - UPDATE with your actual monitor names and fingerprints!
  # Monitor names are typically: eDP-1 (laptop), HDMI-1, DP-1, DP-2, etc.
  # Find yours by running: xrandr --query

  services.autorandr = {
    enable = true;

    profiles = {
      # Mobile profile - only laptop screen
      "mobile" = {
        fingerprint = {
          # REPLACE with your laptop's internal display fingerprint
          # Get it by running: autorandr --fingerprint
          # Example: eDP-1 = "00ffffffffffff004d10...";
        };
        config = {
          # Laptop internal display (typically eDP-1, eDP, or LVDS-1)
          # REPLACE "eDP-1" with your actual laptop display name
          "eDP-1" = {
            enable = true;
            primary = true;
            position = "0x0";
            mode = "1920x1080";  # UPDATE with your laptop's native resolution
            rate = "60.00";
          };
        };
      };

      # Docked profile - 3 monitors (1 laptop + 2 external)
      "docked" = {
        fingerprint = {
          # REPLACE with actual fingerprints from: autorandr --fingerprint
          # You need fingerprints for all three displays
          # eDP-1 = "00ffffffffffff004d10...";
          # DP-1 = "00ffffffffffff0010ac...";
          # DP-2 = "00ffffffffffff0010ac...";
        };
        config = {
          # Laptop display on the left
          # UPDATE display names and positions based on your setup
          "eDP-1" = {
            enable = true;
            position = "0x0";
            mode = "1920x1080";  # UPDATE with your resolution
            rate = "60.00";
          };
          # First external monitor in the center (primary)
          "DP-1" = {
            enable = true;
            primary = true;
            position = "1920x0";  # Right of laptop screen
            mode = "1920x1080";   # UPDATE with your monitor's resolution
            rate = "60.00";
          };
          # Second external monitor on the right
          "DP-2" = {
            enable = true;
            position = "3840x0";  # Right of first external monitor
            mode = "1920x1080";   # UPDATE with your monitor's resolution
            rate = "60.00";
          };
        };
      };

      # Single external monitor (useful for presentations)
      "single-external" = {
        fingerprint = {
          # REPLACE with fingerprints
        };
        config = {
          "eDP-1" = {
            enable = false;  # Disable laptop screen
          };
          "DP-1" = {
            enable = true;
            primary = true;
            position = "0x0";
            mode = "1920x1080";
            rate = "60.00";
          };
        };
      };
    };
  };

  # Systemd service to detect changes and switch profiles
  systemd.user.services.autorandr = {
    description = "Autorandr execution hook";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.autorandr}/bin/autorandr --change";
      RemainAfterExit = false;
    };
  };

  # Udev rule to trigger autorandr on display changes
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="drm", RUN+="${pkgs.systemd}/bin/systemctl --no-block start autorandr.service"
  '';
}
