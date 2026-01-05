{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # VSCodium with extensions - portable across all laptops
    # VSCodium is the open-source build of VSCode without Microsoft telemetry

    environment.systemPackages = with pkgs; [
      # VSCodium base
      (vscode-with-extensions.override {
        vscode = vscodium;
        vscodeExtensions = with vscode-extensions; [
          # Language Support
          ms-python.python                    # Python language support
          ms-python.vscode-pylance            # Python language server
          ms-python.debugpy                   # Python debugger
          jnoortheen.nix-ide                  # Nix language support
          arrterian.nix-env-selector          # Nix environment selector (part of nix extension pack)

          # Development Tools
          mkhl.direnv                         # direnv integration

        ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          # Claude Code extension
          {
            name = "claude-code";
            publisher = "anthropic";
            version = "latest";
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          }
          # Note: You may need to update the version and sha256 hash above
          # or install Claude Code manually via the VSCodium marketplace
          # Check with: codium --list-extensions
        ];
      })
    ];

    # VSCodium user settings
    # Create default settings.json in /etc/vscodium-settings.json
    # Users can symlink this or copy it to ~/.config/VSCodium/User/settings.json
    environment.etc."vscodium-settings.json" = {
      text = builtins.toJSON {
        # Editor Settings
        "editor.fontSize" = 14;
        "editor.fontFamily" = "'Fira Code', 'Droid Sans Mono', 'monospace', monospace";
        "editor.fontLigatures" = true;
        "editor.tabSize" = 2;
        "editor.insertSpaces" = true;
        "editor.detectIndentation" = true;
        "editor.wordWrap" = "on";
        "editor.minimap.enabled" = true;
        "editor.renderWhitespace" = "selection";
        "editor.bracketPairColorization.enabled" = true;
        "editor.guides.bracketPairs" = true;
        "editor.formatOnSave" = false;
        "editor.rulers" = [ 80 120 ];
        "editor.cursorBlinking" = "smooth";
        "editor.cursorSmoothCaretAnimation" = "on";

        # Files
        "files.autoSave" = "afterDelay";
        "files.autoSaveDelay" = 1000;
        "files.trimTrailingWhitespace" = true;
        "files.insertFinalNewline" = true;
        "files.exclude" = {
          "**/.git" = true;
          "**/.svn" = true;
          "**/.hg" = true;
          "**/CVS" = true;
          "**/.DS_Store" = true;
          "**/node_modules" = true;
          "**/__pycache__" = true;
          "**/*.pyc" = true;
        };

        # Git
        "git.autofetch" = true;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;

        # Terminal
        "terminal.integrated.fontSize" = 13;
        "terminal.integrated.fontFamily" = "'Fira Code', monospace";
        "terminal.integrated.cursorBlinking" = true;
        "terminal.integrated.cursorStyle" = "line";

        # Workbench
        "workbench.colorTheme" = "Default Dark Modern";
        "workbench.startupEditor" = "none";
        "workbench.editor.enablePreview" = false;

        # Python
        "python.linting.enabled" = true;
        "python.linting.pylintEnabled" = false;
        "python.formatting.provider" = "none";
        "python.analysis.typeCheckingMode" = "basic";

        # Nix
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "nix.formatterPath" = "nixpkgs-fmt";

        # direnv
        "direnv.restart.automatic" = true;

        # Claude Code
        "claudeCode.environmentVariables" = [];
        "claudeCode.useCtrlEnterToSend" = true;
        "claudeCode.preferredLocation" = "panel";

        # Diff Editor
        "diffEditor.renderSideBySide" = true;

        # Security
        "security.workspace.trust.enabled" = true;
      };
      mode = "0644";
    };

    # VSCodium keybindings
    environment.etc."vscodium-keybindings.json" = {
      text = builtins.toJSON [
        {
          key = "ctrl+shift+f";
          command = "workbench.action.findInFiles";
        }
        {
          key = "ctrl+p";
          command = "workbench.action.quickOpen";
        }
      ];
      mode = "0644";
    };

    # Instructions for users
    environment.etc."vscodium-setup-instructions.txt" = {
      text = ''
        VSCodium Settings Setup
        ═══════════════════════════════════════════════════════════════

        The NixOS configuration has created default VSCodium settings at:
          /etc/vscodium-settings.json
          /etc/vscodium-keybindings.json

        To use these settings, run:

          mkdir -p ~/.config/VSCodium/User
          ln -sf /etc/vscodium-settings.json ~/.config/VSCodium/User/settings.json
          ln -sf /etc/vscodium-keybindings.json ~/.config/VSCodium/User/keybindings.json

        Or copy them if you want to customize:

          mkdir -p ~/.config/VSCodium/User
          cp /etc/vscodium-settings.json ~/.config/VSCodium/User/settings.json
          cp /etc/vscodium-keybindings.json ~/.config/VSCodium/User/keybindings.json

        ═══════════════════════════════════════════════════════════════
      '';
      mode = "0644";
    };

    # Enable the nix-ld module for binary compatibility
    # This is important for extensions with native components
    # Already enabled in laptop-xfce.nix, but ensuring it's available

    # To list your current extensions, run on an existing system:
    # codium --list-extensions
    #
    # To export extension settings:
    # cat ~/.config/VSCodium/User/settings.json
  };
}
