{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    nixpkgs.config.allowUnfree = true;
    
    environment.systemPackages = with pkgs; [
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

          # Don't use anthropic.claude-code here - it has wrong hash
        ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          # Claude Code extension from marketplace with correct hash
          {
            name = "claude-code";
            publisher = "anthropic";
            version = "2.0.75";
            sha256 = "sha256-LXUIp+Rqh0prvFLgmbiSVJYHNY2ECVAfK8GLmDRMcxU=";
          }
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
