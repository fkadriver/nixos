{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    users = {
      users = {
        scott = {
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL4f/6/X75c3fXiXWdLLsJtWyEPxEnwCV7QqjFDLlRk7 scott@scott-ThinkPadT450S"
          ];
          extraGroups = [
            "docker"
            "networkmanager"
            "wheel"
            "video"    # For backlight control
            "plugdev"  # For iPhone/iOS device access
          ];
          hashedPassword = "$y$j9T$PwV0AT33FffSLHl9QH6Uf.$bVwBG9Vy5wH9k0QW7V4fawCa68eCtpCpAOKals3vOF0";
          isNormalUser = true;
        };
      };
    };

    # Trust scott for unrestricted nix settings (e.g. --no-sandbox, --option)
    nix.settings.trusted-users = [ "root" "scott" ];

    # Passwordless sudo for nix and system management commands
    security.sudo.extraRules = [
      {
        users = [ "scott" ];
        commands = [
          {
            command = "/nix/store/*/bin/tailscale *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/tailscale *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nix *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nix-env *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/nix/store/*/bin/nix-env *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/nix/store/*/bin/switch-to-configuration *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # SSH configuration (agent started by desktop environment)
    programs.ssh = {
      extraConfig = ''
        # Automatically add keys to agent when first used
        AddKeysToAgent yes

        # Default identity files (loaded in order)
        IdentityFile ~/.ssh/id_ed25519
        IdentityFile ~/.ssh/id_ed25519_legacy

        # GitHub
        Host github.com
          IdentityFile ~/.ssh/id_ed25519_legacy
          IdentitiesOnly yes

        # Legacy systems
        Host *.local 192.168.*.*
          IdentityFile ~/.ssh/id_ed25519_legacy
          IdentitiesOnly yes
      '';
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

    # Starship prompt configuration is now managed by home-manager
    # See: homeConfigurations/scott.nix
  };
}
