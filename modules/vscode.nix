{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # Allow unfree packages (needed for Claude Code and VSCode)
    nixpkgs.config.allowUnfree = true;
    
    environment.systemPackages = with pkgs; [
      # Add Claude Code
      claude-code
      
      (vscode-with-extensions.override {
        vscode = vscode;
        vscodeExtensions = with vscode-extensions; [
          # Nix language support
          jnoortheen.nix-ide

          # Python support
          ms-python.python
          ms-python.vscode-pylance

          # Tailscale extension
          tailscale.vscode-tailscale
        ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          # Add any additional extensions from marketplace here if needed
        ];
      })
    ];

    # VSCode settings that apply system-wide
    # Users can override these in their own settings.json
    environment.etc."vscode-settings.json".text = builtins.toJSON {
      # Nix IDE settings
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "${pkgs.nil}/bin/nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = [ "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" ];
          };
        };
      };

      # Python settings
      "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python3";
      "python.analysis.typeCheckingMode" = "basic";

      # General editor settings
      "editor.formatOnSave" = true;
      "editor.tabSize" = 2;
      "files.autoSave" = "afterDelay";
      "files.autoSaveDelay" = 1000;

      # Telemetry
      "telemetry.telemetryLevel" = "off";
    };
  };
}