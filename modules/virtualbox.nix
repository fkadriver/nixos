{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Enable VirtualBox
    virtualisation.virtualbox.host = {
      enable = true;
      enableExtensionPack = true;  # For USB 2.0/3.0, RDP, etc.
    };

    # Add user scott to vboxusers group for VirtualBox access
    users.users.scott.extraGroups = [ "vboxusers" ];
  };
}
