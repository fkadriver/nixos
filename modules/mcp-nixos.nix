{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.mcp-nixos;
  # Absolute store path, not a bare "mcp-nixos": Claude Code may be launched
  # from contexts (IDE extensions, systemd user units) whose PATH lacks
  # /run/current-system/sw/bin.
  server = {
    type = "stdio";
    command = "${cfg.package}/bin/mcp-nixos";
    args = [ ];
  };
in
{
  options.programs.mcp-nixos = {
    enable = mkEnableOption "mcp-nixos Claude Code MCP server";

    package = mkPackageOption pkgs "mcp-nixos" { };

    user = mkOption {
      type = types.str;
      default = "scott";
      description = "User whose Claude Code user-scope MCP config to manage";
    };

    homeDir = mkOption {
      type = types.str;
      default = "/home/scott";
      description = "Home directory of the configured user";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Claude Code reads user-scope MCP servers from ~/.claude.json, NOT
    # ~/.claude/settings.json (mcpServers there is silently ignored — that's
    # why the old uvx-based entry never showed up in `claude mcp list`).
    # ~/.claude.json is also Claude Code's own live state file, so only the
    # one key is touched, written via temp file + mv, and only when it differs.
    system.activationScripts.mcp-nixos = lib.stringAfter [ "users" ] ''
      JQ=${pkgs.jq}/bin/jq
      CLAUDE_JSON="${cfg.homeDir}/.claude.json"
      SETTINGS="${cfg.homeDir}/.claude/settings.json"
      WANT=${escapeShellArg (builtins.toJSON server)}

      [ -s "$CLAUDE_JSON" ] || printf '{}\n' > "$CLAUDE_JSON"
      if ! $JQ -e --argjson want "$WANT" '.mcpServers.nixos == $want' "$CLAUDE_JSON" >/dev/null 2>&1; then
        TMP=$(mktemp "$CLAUDE_JSON.XXXXXX")
        if $JQ --argjson want "$WANT" '.mcpServers.nixos = $want' "$CLAUDE_JSON" > "$TMP"; then
          chown ${cfg.user}: "$TMP"
          chmod 600 "$TMP"
          mv "$TMP" "$CLAUDE_JSON"
        else
          rm -f "$TMP"
        fi
      fi
      chown ${cfg.user}: "$CLAUDE_JSON"

      # Drop the dead entry the previous version of this module wrote.
      if [ -f "$SETTINGS" ] && $JQ -e '.mcpServers.nixos' "$SETTINGS" >/dev/null 2>&1; then
        TMP=$(mktemp "$SETTINGS.XXXXXX")
        if $JQ 'del(.mcpServers.nixos) | if .mcpServers == {} then del(.mcpServers) else . end' "$SETTINGS" > "$TMP"; then
          chown ${cfg.user}: "$TMP"
          mv "$TMP" "$SETTINGS"
        else
          rm -f "$TMP"
        fi
      fi
    '';
  };
}
