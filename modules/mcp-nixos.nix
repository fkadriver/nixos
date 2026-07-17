{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.mcp-nixos;
in
{
  options.programs.mcp-nixos = {
    enable = mkEnableOption "mcp-nixos Claude Code MCP server";

    user = mkOption {
      type = types.str;
      default = "scott";
      description = "User whose ~/.claude/settings.json to configure";
    };

    homeDir = mkOption {
      type = types.str;
      default = "/home/scott";
      description = "Home directory of the configured user";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.uv ];

    system.activationScripts.mcp-nixos = ''
      CLAUDE_DIR="${cfg.homeDir}/.claude"
      SETTINGS="$CLAUDE_DIR/settings.json"
      mkdir -p "$CLAUDE_DIR"

      if [ ! -f "$SETTINGS" ]; then
        printf '{}' > "$SETTINGS"
      fi

      UPDATED=$(${pkgs.jq}/bin/jq \
        '.mcpServers.nixos = {"command": "uvx", "args": ["mcp-nixos"]}' \
        "$SETTINGS")
      printf '%s\n' "$UPDATED" > "$SETTINGS"
      chown -R ${cfg.user}: "$CLAUDE_DIR" 2>/dev/null || true
    '';
  };
}
