{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules.syncthing-declarative
  ];

  services.syncthing-declarative = {
    enable = true;
    deviceName = "latitude";

    folders = {
      documents = {
        path = "/home/scott/Documents";
        devices = [ "airbook" "server" ];
        versioning = {
          type = "simple";
          params.keep = "5";  # Keep 5 old versions
        };
      };

      ssh = {
        path = "/home/scott/.ssh";
        devices = [ "airbook" "server" ];
        ignorePerms = false;  # Preserve permissions for SSH keys
      };
    };
  };
}
