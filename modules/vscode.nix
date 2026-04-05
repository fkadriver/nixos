{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.config.allowUnfree = true;

    # Enable gnome-keyring for VSCode settings sync
    services.gnome.gnome-keyring.enable = true;

    # Enable PAM integration for auto-unlock on login
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.lightdm.enableGnomeKeyring = true;
    security.pam.services.gdm.enableGnomeKeyring = true;

    # Enable nix-ld for extensions with native binaries (Claude Code, etc.)
    programs.nix-ld.enable = true;

    # Install VS Code and supporting tools
    # Extensions are managed via VS Code Settings Sync (GitHub account)
    # This allows installing any marketplace extension without Nix store limitations
    environment.systemPackages = with pkgs; [
      (vscode-with-extensions.override {
        vscodeExtensions = [
          vscode-extensions.dracula-theme.theme-dracula
        ];
      })
      libsecret
      gnome-keyring
      seahorse            # GUI for managing keyrings
      clang-tools         # clangd for C/C++ language server
      nil                 # Nix language server
      nixpkgs-fmt         # Nix formatter
    ];

    # Recommended extensions (install via marketplace, sync via GitHub):
    # - jnoortheen.nix-ide           # Nix language support
    # - llvm-vs-code-extensions.vscode-clangd  # C/C++ support
    # - ms-python.python             # Python support
    # - ms-python.vscode-pylance     # Python IntelliSense
    # - continue.continue            # AI/LLM assistant
    # - tailscale.vscode-tailscale   # Tailscale integration
    # - ms-azuretools.vscode-docker  # Docker support
    # - ms-vscode-remote.remote-ssh  # Remote SSH
    # - ms-vscode-remote.remote-containers  # Dev containers
    # - github.vscode-pull-request-github   # GitHub PRs
    # - github.vscode-github-actions        # GitHub Actions
    # - anthropic.claude-code        # Claude Code AI assistant

    # Reference settings for Nix IDE (configure in VS Code settings.json):
    # {
    #   "nix.enableLanguageServer": true,
    #   "nix.serverPath": "nil",
    #   "nix.serverSettings": {
    #     "nil": { "formatting": { "command": ["nixpkgs-fmt"] } }
    #   }
    # }
  };
}
