{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    services = {
      syncthing = {
        dataDir = /home/scott;
        enable = true;
        guiAddress = "0.0.0.0:8384";
        overrideDevices = true;
        overrideFolders = true;
        settings = {
          folders = "Documents" = {
          path = "/home/scott/Documents";
          ignorPerms = true;
        };
      };
      user = "scott";
    };
  };
};
}
