# Example configuration for iDrive e360 cloud backup
#
# This file shows different ways to configure iDrive e360 in your NixOS system.
# Copy the relevant sections to your host configuration file (e.g., hosts/latitude.nix)

{
  # Example 1: Basic configuration with local .deb file
  services.idrive-e360 = {
    enable = true;
    debFile = /home/scott/Downloads/idrive360.deb;
    user = "scott";
  };

  # Example 2: With scheduled daily backups at 2 AM
  services.idrive-e360 = {
    enable = true;
    debFile = /home/scott/Downloads/idrive360.deb;
    user = "scott";

    scheduledBackup = {
      enable = true;
      schedule = "02:00";  # Daily at 2 AM
    };
  };

  # Example 3: Weekly backups on Sundays at 3 AM
  services.idrive-e360 = {
    enable = true;
    debFile = /home/scott/Downloads/idrive360.deb;
    user = "scott";

    scheduledBackup = {
      enable = true;
      schedule = "Sun 03:00";
    };
  };

  # Example 4: Custom directories and no auto-start
  services.idrive-e360 = {
    enable = true;
    debFile = /home/scott/Downloads/idrive360.deb;
    user = "scott";
    configDir = "/home/scott/.config/idrive360";
    dataDir = "/home/scott/Documents";  # Only backup Documents
    autoStart = false;  # Manual start only

    scheduledBackup = {
      enable = true;
      schedule = "hourly";  # Backup every hour
    };
  };

  # Example 5: Server configuration (minimal, scheduled backups only)
  services.idrive-e360 = {
    enable = true;
    debFile = /root/idrive360.deb;
    user = "root";
    autoStart = false;  # Don't run daemon, only scheduled backups

    scheduledBackup = {
      enable = true;
      schedule = "daily";  # Once per day
    };
  };
}

# Advanced systemd timer schedules:
#
# "minutely"          - Every minute
# "hourly"            - Every hour
# "daily"             - Once per day (midnight)
# "weekly"            - Once per week (Monday midnight)
# "monthly"           - Once per month (1st at midnight)
# "00:00"             - Daily at midnight
# "02:30"             - Daily at 2:30 AM
# "Mon 09:00"         - Mondays at 9 AM
# "Mon,Fri 18:00"     - Mondays and Fridays at 6 PM
# "Mon..Fri 09:00"    - Weekdays at 9 AM
# "*-*-* 00/4:00:00"  - Every 4 hours
#
# See: man systemd.time(7) for full syntax
