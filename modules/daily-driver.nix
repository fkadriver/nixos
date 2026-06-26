{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  imports = [
    inputs.self.nixosModules.games
    inputs.self.nixosModules."3d-printing"
    inputs.self.nixosModules.font
    inputs.self.nixosModules.printing
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.bitwarden-scott
    inputs.self.nixosModules.borg-backup
    inputs.self.nixosModules.home-design
    inputs.self.nixosModules.iphone
    inputs.self.nixosModules.syncthing-declarative
    inputs.self.nixosModules.vscode
    inputs.home-manager.nixosModules.home-manager
    (inputs.self.homeConfigurations.scott).nixosModule
  ];

  config = {

    # Fonts: managed by modules/font.nix
    my.fonts = {
      enable = true;
      documents = true;
      craft = true;
      printing3d = true;
      nerd = true;
      viewer = true;
    };


    networking.networkmanager.enable = true;

    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    # Enable keyboard backlight control for laptops (Dell, Lenovo, etc.)
    services.udev.extraRules = ''
      # Allow members of video group to control keyboard backlight
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';

    programs.firefox.enable = true;

    environment.systemPackages = with pkgs; [
      python3Minimal
      claude-code

      shotwell
      handbrake  # Video transcoding
      zoom-us

      libreoffice
      thunderbird

      borgbackup
      unzip
      usbimager  # Write .img/.iso files to USB drives
      gparted    # Disk partitioning and formatting

      # 2D CAD
      librecad
      qcad

      # Backlight control (for screen and keyboard backlighting)
      brightnessctl
    ];

    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib zstd bzip2 xz
        openssl libxcrypt libxcrypt-legacy
        curl libssh
        util-linux systemd attr acl libsodium
        libxml2 glib dbus
        libGL          # OpenCV / mediapipe / GPU ML backends
        libxcb         # OpenCV display support
      ];
    };
    my.printing = {
      enable = true;
      fonts.enable = true;
      repairTools = true;
      generateTestArtifacts = true;
    };
  };
}
