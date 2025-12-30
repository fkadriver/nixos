{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    services = {
      syncthing = {
        dataDir = "/home/scott";
        enable = true;
        overrideDevices = false;
        overrideFolders = false;
        user = "scott";
      };
    };
  };
}
