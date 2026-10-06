# OpenLogi (https://openlogi.org) is a modern replacement for Solaar —
# no Logitech account, no telemetry. In nixpkgs as of PR #527640 (merged; v0.6.25,
# x86_64-linux + darwin). Upstream is v0.8.11. Cross-platform (Linux/macOS/Windows),
# so it can cover both latitude and airbook-darwin — Solaar cannot.
# Evaluate migration: fn-swap and Screen Capture divert look covered; verify K860
# Host Switch mapping on Mac before switching.
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Enable Solaar service for Logitech device management
    programs.solaar = {
      enable = true;
      userService = {
        enable = true;
        window = "hide";  # Start hidden in system tray
      };
    };

    # Enable udev rules for Logitech devices
    hardware.logitech.wireless.enable = true;

    # Install libinput-gestures for mouse button support
    environment.systemPackages = with pkgs; [
      libinput  # For debugging input devices
      evtest    # For testing input events
      xdotool   # For simulating key presses (X11)
      xbindkeys # For binding mouse buttons to actions
    ];

    # Enable Num Lock at login screen and session start
    services.displayManager.sddm.autoNumlock = true;
    services.xserver.displayManager.sessionCommands = ''
      ${pkgs.numlockx}/bin/numlockx on
    '';

    home-manager.users.scott = { ... }: {
      # Solaar rules for ERGO K860 for Business (connected via Bolt receiver):
      #
      # 1. fn-swap=false: F1-F12 send standard keycodes by default; Fn+Fx sends special function.
      #    This is enforced at login by the solaar-k860-setup service below.
      #
      # 2. Screen Capture key (Fn+F7) -> launch Spectacle (KDE screenshot tool)
      #    "Screen Capture" is the special function on F7 (pos:7 in fn row).
      #    With fn-swap=false, Fn+F7 fires "Screen Capture"; this rule launches spectacle directly
      #    rather than sending Print, since KDE Plasma doesn't bind Print to spectacle by default.
      #
      home.file.".config/solaar/rules.yaml" = {
        text = ''
          %YAML 1.3
          ---
          - Rule:
            - Device: ERGO K860 for Business
            - Rule:
              - Key: [Screen Capture, pressed]
              - Execute: spectacle
          ...
        '';
        # Solaar reads rules.yaml but only writes config.yaml; this file is safe as read-only.
        force = true;
      };
    };

    # Apply ERGO K860 settings on each login via solaar CLI.
    # fn-swap=false: F1-F12 are standard keycodes by default (Fn+Fx = special).
    # Divert Screen Capture (Fn+F7) so rules.yaml can intercept it and launch Spectacle.
    systemd.user.services.solaar-k860-setup = {
      description = "Apply Solaar settings for ERGO K860 for Business";
      wantedBy = [ "graphical-session.target" ];
      after = [ "solaar.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "solaar-k860-setup" ''
          # Wait for Solaar to enumerate devices
          sleep 3
          DEV="ERGO K860 for Business"
          ${config.programs.solaar.package}/bin/solaar config "$DEV" fn-swap false
          ${config.programs.solaar.package}/bin/solaar config "$DEV" divert-keys "Screen Capture" Diverted

          # Remove stale Wave Keys entry from config.yaml (device no longer paired)
          CONFIG="$HOME/.config/solaar/config.yaml"
          if [ -f "$CONFIG" ] && grep -q "Wave Keys" "$CONFIG"; then
            ${pkgs.python3}/bin/python3 - <<'PYEOF'
          import yaml, os
          path = os.path.expanduser("~/.config/solaar/config.yaml")
          with open(path) as f:
              data = yaml.safe_load(f)
          data = [e for e in data if not (isinstance(e, dict) and e.get("_NAME") == "Wave Keys")]
          with open(path, "w") as f:
              yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
          PYEOF
          fi
        '';
      };
    };
  };
}
