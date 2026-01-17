{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: 

let
  # Create a patched version of the Claude Code extension
  claude-code-patched = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "claude-code";
      publisher = "anthropic";
      version = "2.0.75";
      # Specify linux-x64 platform to get correct binary
      arch = "linux-x64";
      sha256 = "sha256-c6h6IlsmiE2bkVIq9DCANqo5a+wkSCZo1Ok5xI5xihI=";
    };
    
    nativeBuildInputs = with pkgs; [ 
      autoPatchelfHook
    ];
    
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
    ];
    
    postInstall = ''
      # Find and patch the claude binary
      if [ -f "$out/share/vscode/extensions/anthropic.claude-code/resources/native-binary/claude" ]; then
        chmod +x "$out/share/vscode/extensions/anthropic.claude-code/resources/native-binary/claude"
        echo "Patching Claude binary..."
      fi
    '';
  };
in
{
  config = {
    nixpkgs.config.allowUnfree = true;

    # Enable gnome-keyring for VSCode settings sync
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.gdm.enableGnomeKeyring = true;

    # Install libsecret for keyring access
    environment.systemPackages = with pkgs; [
      libsecret
      gnome-keyring
      (vscode-with-extensions.override {
        vscode = vscode;
        vscodeExtensions = with vscode-extensions; [
          # Nix language support
          jnoortheen.nix-ide

          # Python support
          ms-python.python
          ms-python.vscode-pylance

          # ChatGPT / LLM
          continue.continue

          # Tailscale extension
          tailscale.vscode-tailscale

          # Docker and container support
          ms-azuretools.vscode-docker
          ms-vscode-remote.remote-containers
        ] ++ [
          # Patched Claude Code extension
          claude-code-patched
        ];
      })
    ];

    # VSCode settings that apply system-wide
    environment.etc."vscode-settings.json".text = builtins.toJSON {
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "${pkgs.nil}/bin/nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = [ "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" ];
          };
        };
      };
      "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python3";
      "python.analysis.typeCheckingMode" = "basic";
      "editor.formatOnSave" = true;
      "editor.tabSize" = 2;
      "files.autoSave" = "afterDelay";
      "files.autoSaveDelay" = 1000;
      "telemetry.telemetryLevel" = "off";
    };
  };
}
