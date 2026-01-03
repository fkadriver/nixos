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
          jnoortheen.nix-ide                  # Nix language support
          bbenoist.nix                        # Nix syntax highlighting (alternative)

          # Code Quality & Formatting
          esbenp.prettier-vscode              # Code formatter for web dev
          dbaeumer.vscode-eslint              # JavaScript/TypeScript linting

          # Git Integration
          eamodio.gitlens                     # Enhanced Git capabilities
          mhutchie.git-graph                  # Git graph visualization
          github.vscode-pull-request-github   # GitHub PR integration

          # Remote Development
          ms-vscode-remote.remote-ssh         # SSH remote development

          # Productivity
          vscodevim.vim                       # Vim emulation
          usernamehw.errorlens                # Inline error highlighting
          oderwat.indent-rainbow              # Colorize indentation levels

          # Markdown & Documentation
          yzhang.markdown-all-in-one          # Markdown shortcuts and preview
          bierner.markdown-mermaid            # Mermaid diagram support

          # Docker & Containers
          ms-azuretools.vscode-docker         # Docker support

          # Themes (optional - customize as needed)
          pkief.material-icon-theme           # Material Design icons

        ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          # Claude Code extension (if not available in nixpkgs)
          # Note: You may need to add claude-code separately if it's installed manually
          # Check your current extensions with: codium --list-extensions
        ];
      })
    ];

    # VSCodium settings and keybindings can be managed via home-manager or
    # manually synced via Settings Sync extension or Git repository

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
