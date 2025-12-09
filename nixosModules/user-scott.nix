{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    users = {
      users = {
        scott = {
          extraGroups = [
            "docker"
            "networkmanager"
            "wheel"
          ];
          hashedPassword = "$y$j9T$PwV0AT33FffSLHl9QH6Uf.$bVwBG9Vy5wH9k0QW7V4fawCa68eCtpCpAOKals3vOF0";
          isNormalUser = true;
        };
      };
    };
  };
}
