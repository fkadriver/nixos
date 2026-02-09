{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.vscode-server.nixosModules.default
  ];

  config = {
    services.vscode-server.enable = true;
  };
}
