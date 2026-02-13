{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  imports = [
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

    programs.firefox.enable = true;

    environment.systemPackages = with pkgs; [
      python3Minimal
      claude-code

      heroic
      lutris
      wineWowPackages.stable
      winetricks

      shotwell

      libreoffice
      thunderbird

      borgbackup
      unzip

      dejavu_fonts
      font-manager
      fontforge
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
      ];
    };
    my.printing = {
      enable = true;
      generateTestArtifacts = true;
    };
  };
}
