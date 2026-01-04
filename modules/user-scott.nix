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
            "plugdev"  # For iPhone/iOS device access
          ];
          hashedPassword = "$y$j9T$PwV0AT33FffSLHl9QH6Uf.$bVwBG9Vy5wH9k0QW7V4fawCa68eCtpCpAOKals3vOF0";
          isNormalUser = true;
        };
      };
    };

    # Git configuration for user scott
    programs.git = {
      enable = true;
      config = {
        user = {
          name = "Scott Jensen";
          email = "fkadriver@gmail.com";
        };
        init = {
          defaultBranch = "main";
        };
        pull = {
          rebase = false;  # Use merge strategy (can change to true for rebase)
        };
        push = {
          autoSetupRemote = true;  # Automatically set up tracking for new branches
        };
        core = {
          editor = "vim";
        };
        # Helpful aliases built into git config
        alias = {
          st = "status";
          co = "checkout";
          br = "branch";
          ci = "commit";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          lg = "log --graph --oneline --decorate --all";
        };
      };
    };
  };
}
