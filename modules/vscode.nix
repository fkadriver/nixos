{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  # VSCode and dev-tool CLIs don't need to be bleeding-edge — pull them from
  # the better-cached nixos-unstable input. gnome-keyring/libsecret/seahorse
  # stay on the base pkgs since they're wired through services.gnome.gnome-keyring
  # and PAM below, from the same revision as the rest of the login stack.
  pkgsNixos = inputs.nixpkgs-nixos.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
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
    environment.systemPackages = (with pkgs; [
      libsecret
      gnome-keyring
      seahorse            # GUI for managing keyrings
    ]) ++ (with pkgsNixos; [
      vscode              # Plain VS Code - extensions installed via marketplace
      clang-tools         # clangd for C/C++ language server
      nil                 # Nix language server
      nixpkgs-fmt         # Nix formatter
    ]);

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
