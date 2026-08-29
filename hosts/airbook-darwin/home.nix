{ config, lib, pkgs, ... }:
let
  # Fetches the borg passphrase from Bitwarden using stored API credentials
  borgPassCmd = pkgs.writeShellScript "borg-getpass" ''
    export BW_CLIENTID="$(cat "$HOME/.local/share/bitwarden-secrets/client_id")"
    export BW_CLIENTSECRET="$(cat "$HOME/.local/share/bitwarden-secrets/client_secret")"
    export BW_PASSWORD="$(cat "$HOME/.local/share/bitwarden-secrets/master_password")"
    /usr/local/bin/bw login --apikey --quiet 2>/dev/null || true
    export BW_SESSION="$(/usr/local/bin/bw unlock --passwordenv BW_PASSWORD --raw)"
    /usr/local/bin/bw get item "91db7811-ddf1-49aa-8a42-b3d60188a6e6" \
      | ${pkgs.jq}/bin/jq -r '.login.password'
  '';
  borgRepo = "ssh://scott@nas01.warthog-royal.ts.net/pool/borg/airbook-darwin";
  borgEnv  = ''BORG_RSH="ssh -i $HOME/.ssh/id_ed25519_legacy -o StrictHostKeyChecking=accept-new" BORG_PASSCOMMAND="${borgPassCmd}" BORG_REMOTE_PATH=/run/current-system/sw/bin/borg'';
in
{
  home = {
    username = "scott";
    homeDirectory = "/Users/scott";
    stateVersion = "24.11";
    # home-manager (unstable, shared with NixOS hosts) doesn't strictly need to
    # match nixpkgs-26.05-darwin — silence the release-check assertion.
    enableNixpkgsReleaseCheck = false;

    # Add ~/.local/bin to PATH
    sessionPath = [ "$HOME/.local/bin" "$HOME/go/bin" ];

    # Symlink orca-settings repo as OrcaSlicer user config (runs after each rebuild).
    # No-op if the repo hasn't been cloned yet.
    activation.orcaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      REPO="$HOME/git/orca-settings"
      ORCA_DIR="$HOME/Library/Application Support/OrcaSlicer"
      if [ -d "$REPO" ]; then
        mkdir -p "$ORCA_DIR"
        if [ ! -L "$ORCA_DIR/user" ]; then
          rm -rf "$ORCA_DIR/user"
          ln -sfn "$REPO" "$ORCA_DIR/user"
        fi
      fi
    '';

    # Wire up mcp-nixos MCP server for Claude Code
    activation.mcp-nixos = lib.hm.dag.entryAfter ["writeBoundary"] ''
      CLAUDE_DIR="$HOME/.claude"
      SETTINGS="$CLAUDE_DIR/settings.json"
      mkdir -p "$CLAUDE_DIR"

      if [ ! -f "$SETTINGS" ]; then
        printf '{}' > "$SETTINGS"
      fi

      UPDATED=$(${pkgs.jq}/bin/jq \
        '.mcpServers.nixos = {"command": "uvx", "args": ["mcp-nixos"]}' \
        "$SETTINGS")
      printf '%s\n' "$UPDATED" > "$SETTINGS"
    '';

    # Set Geany as default for .txt and .conf files via duti
    activation.geanyDefaultEditor = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if command -v duti >/dev/null 2>&1; then
        duti -s org.geany.Geany .txt all
        duti -s org.geany.Geany .conf all
      fi
    '';

    # User packages (in addition to system packages)
    packages = with pkgs; [
      # Development
      go
      nodejs
      python3
      # claude-code  # Disabled: build fails on macOS (npm dependency issues)

      # Nix development tools (for VS Code Nix IDE)
      nil            # Nix language server
      nixpkgs-fmt    # Nix formatter

      # Utilities
      age
      htop
      sops

      # 3D printing fonts (from 3d-printing.nix)
      eb-garamond
      libre-baskerville
      oldstandard
      junicode
      inter
      source-sans
    ];
  };

  # SwiftBar plugin — Syncthing status in the macOS menubar. Talks to the brew-managed
  # syncthing daemon via its REST API; keeps the daemon out of the app bundle so it
  # survives `brew upgrade syncthing` cleanly (unlike the `syncthing-app` cask which
  # embeds its own daemon and would fight the brew one for the config directory).
  # Filename `.30s.` = refresh every 30 seconds. On SwiftBar first launch, point it at
  # `~/Library/Application Support/SwiftBar/Plugins/` (this directory).
  home.file."Library/Application Support/SwiftBar/Plugins/syncthing.30s.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # <xbar.title>Syncthing</xbar.title>
      # <xbar.version>v1.0</xbar.version>
      # <xbar.author>Scott</xbar.author>
      # <xbar.desc>Local Syncthing daemon status via REST API.</xbar.desc>
      # <xbar.dependencies>bash,curl,jq,xmllint</xbar.dependencies>
      # <swiftbar.hideAbout>true</swiftbar.hideAbout>
      # <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
      # <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

      set -eu
      # SwiftBar-invoked scripts inherit a minimal PATH; add the nix profile so jq is found.
      export PATH="/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

      CONFIG="$HOME/Library/Application Support/Syncthing/config.xml"
      API_URL="http://127.0.0.1:8384"

      if [ ! -f "$CONFIG" ]; then
        echo "ST off"; echo "---"; echo "config.xml not found"; exit 0
      fi

      API_KEY=$(/usr/bin/xmllint --xpath 'string(/configuration/gui/apikey)' "$CONFIG" 2>/dev/null || true)
      if [ -z "$API_KEY" ]; then
        echo "ST ?"; echo "---"; echo "API key not found in config.xml"; exit 0
      fi

      api() { curl -sS --connect-timeout 2 --max-time 5 -H "X-API-Key: $API_KEY" "$API_URL/rest/$1" 2>/dev/null; }

      if ! api system/ping >/dev/null 2>&1; then
        echo "ST × | color=red"; echo "---"
        echo "daemon unreachable"
        echo "Open Web UI | href=$API_URL"
        exit 0
      fi

      status=$(api system/status || echo '{}')
      conns=$(api system/connections || echo '{}')
      ver=$(api system/version || echo '{}')

      peers_up=$(echo "$conns" | jq -r '[.connections // {} | to_entries[] | select(.value.connected==true)] | length' 2>/dev/null || echo "?")
      peers_all=$(echo "$conns" | jq -r '[.connections // {} | to_entries[]] | length' 2>/dev/null || echo "?")
      version=$(echo "$ver" | jq -r '.version // "?"')
      uptime=$(echo "$status" | jq -r '.uptime // 0')
      uptime_h=$(( uptime / 3600 ))

      echo "ST $peers_up/$peers_all"
      echo "---"
      echo "Syncthing $version"
      echo "Peers connected: $peers_up of $peers_all"
      echo "Uptime: ''${uptime_h}h"
      echo "---"
      echo "Open Web UI | href=$API_URL"
    '';
  };

  # iTerm2 Dracula color theme (auto-loaded as a Dynamic Profile)
  home.file."Library/Application Support/iTerm2/DynamicProfiles/dracula.json".text = builtins.toJSON {
    Profiles = [
      {
        Name = "Dracula";
        Guid = "dracula-iterm2-profile";
        "Background Color"         = { "Red Component" = 0.1569; "Green Component" = 0.1647; "Blue Component" = 0.2118; "Alpha Component" = 1; };
        "Foreground Color"         = { "Red Component" = 0.9725; "Green Component" = 0.9725; "Blue Component" = 0.9490; "Alpha Component" = 1; };
        "Cursor Color"             = { "Red Component" = 0.9725; "Green Component" = 0.9725; "Blue Component" = 0.9490; "Alpha Component" = 1; };
        "Cursor Text Color"        = { "Red Component" = 0.1569; "Green Component" = 0.1647; "Blue Component" = 0.2118; "Alpha Component" = 1; };
        "Selection Color"          = { "Red Component" = 0.2667; "Green Component" = 0.2784; "Blue Component" = 0.3529; "Alpha Component" = 1; };
        "Selected Text Color"      = { "Red Component" = 0.9725; "Green Component" = 0.9725; "Blue Component" = 0.9490; "Alpha Component" = 1; };
        # ANSI normal
        "Ansi 0 Color"  = { "Red Component" = 0.1294; "Green Component" = 0.1333; "Blue Component" = 0.1725; "Alpha Component" = 1; }; # #21222C
        "Ansi 1 Color"  = { "Red Component" = 1.0000; "Green Component" = 0.3333; "Blue Component" = 0.3333; "Alpha Component" = 1; }; # #FF5555
        "Ansi 2 Color"  = { "Red Component" = 0.3137; "Green Component" = 0.9804; "Blue Component" = 0.4824; "Alpha Component" = 1; }; # #50FA7B
        "Ansi 3 Color"  = { "Red Component" = 0.9451; "Green Component" = 0.9804; "Blue Component" = 0.5490; "Alpha Component" = 1; }; # #F1FA8C
        "Ansi 4 Color"  = { "Red Component" = 0.7412; "Green Component" = 0.5765; "Blue Component" = 0.9765; "Alpha Component" = 1; }; # #BD93F9
        "Ansi 5 Color"  = { "Red Component" = 1.0000; "Green Component" = 0.4745; "Blue Component" = 0.7765; "Alpha Component" = 1; }; # #FF79C6
        "Ansi 6 Color"  = { "Red Component" = 0.5451; "Green Component" = 0.9137; "Blue Component" = 0.9922; "Alpha Component" = 1; }; # #8BE9FD
        "Ansi 7 Color"  = { "Red Component" = 0.9725; "Green Component" = 0.9725; "Blue Component" = 0.9490; "Alpha Component" = 1; }; # #F8F8F2
        # ANSI bright
        "Ansi 8 Color"  = { "Red Component" = 0.3843; "Green Component" = 0.4471; "Blue Component" = 0.6431; "Alpha Component" = 1; }; # #6272A4
        "Ansi 9 Color"  = { "Red Component" = 1.0000; "Green Component" = 0.4314; "Blue Component" = 0.4314; "Alpha Component" = 1; }; # #FF6E6E
        "Ansi 10 Color" = { "Red Component" = 0.4118; "Green Component" = 1.0000; "Blue Component" = 0.5804; "Alpha Component" = 1; }; # #69FF94
        "Ansi 11 Color" = { "Red Component" = 1.0000; "Green Component" = 1.0000; "Blue Component" = 0.6471; "Alpha Component" = 1; }; # #FFFFA5
        "Ansi 12 Color" = { "Red Component" = 0.8392; "Green Component" = 0.6745; "Blue Component" = 1.0000; "Alpha Component" = 1; }; # #D6ACFF
        "Ansi 13 Color" = { "Red Component" = 1.0000; "Green Component" = 0.5725; "Blue Component" = 0.8745; "Alpha Component" = 1; }; # #FF92DF
        "Ansi 14 Color" = { "Red Component" = 0.6431; "Green Component" = 1.0000; "Blue Component" = 1.0000; "Alpha Component" = 1; }; # #A4FFFF
        "Ansi 15 Color" = { "Red Component" = 1.0000; "Green Component" = 1.0000; "Blue Component" = 1.0000; "Alpha Component" = 1; }; # #FFFFFF
      }
    ];
  };

  programs = {
    bash = {
      enable = true;
      historySize = 10000;
      historyFileSize = 100000;
      historyControl = [ "ignoredups" "ignorespace" ];
      shellOptions = [
        "histappend"
        "checkwinsize"
        "extglob"
        "globstar"
        "checkjobs"
      ];
      shellAliases = {
        # Basic (from shell-aliases.nix)
        wtf = "alias";
        clr = "clear";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        backup = "tailscale ssh nas01-backup";
        log01 = "tailscale ssh log01";
        pihole01 = "tailscale ssh pihole01";
        pihole02 = "tailscale ssh pihole02";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
        vm01 = "tailscale ssh vm01";
        otworkstation = "tailscale ssh OTworkstation";
        ot = "tailscale ssh OTworkstation";

        # Tailscale troubleshooting
        ts-status = "tailscale status";
        ts-up = "sudo tailscale up";
        ts-down = "sudo tailscale down";
        ts-netcheck = "tailscale netcheck";
        ts-ip = "tailscale ip";
        ts-peers = "tailscale status --peers";
        ts-debug = "tailscale debug";
        # Enabled features for a node: no arg = self, or pass a hostname for a peer
        ts-info = ''f(){ if [ -z "$1" ]; then tailscale status --json | jq '.Self | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry, SSH: ((.Capabilities // []) | any(. == "https://tailscale.com/cap/ssh"))}'; else out=$(tailscale status --json | jq --arg h "$1" '.Peer[] | select((.HostName|ascii_downcase) == ($h|ascii_downcase)) | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry}'); if [ -z "$out" ]; then echo "ts-info: no peer matching '$1'" >&2; else echo "$out"; fi; fi; }; f'';

        # Grep with color
        gpc = "grep --color=always";

        # Git shortcuts
        g = "git";
        gs = "git status";
        ga = "git add";
        gaa = "git add -A";
        gc = "git commit";
        gcm = "git commit -m";
        gp = "git push";
        gpl = "git pull";
        gd = "git diff";
        gdc = "git diff --cached";
        gl = "git log --oneline --graph --decorate";
        gla = "git log --oneline --graph --decorate --all";
        gco = "git checkout";
        gb = "git branch";
        gba = "git branch -a";
        gf = "git fetch";
        gr = "git restore";
        grs = "git restore --staged";

        # Nix shortcuts
        nixdir = "cd ~/git/nixos";
        nix-update = "nix flake update";

        # Common utilities
        ll = "ls -lah";
        la = "ls -A";
        l = "ls -CF";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Borg backup (darwin - uses launchd instead of systemd)
        borg-status = "sudo launchctl list com.local.borg-backup";
        borg-logs   = "tail -100 $HOME/.local/share/borg/backup.log";
        borg-run    = "sudo launchctl start com.local.borg-backup";
        borg-list   = "env ${borgEnv} borg list ${borgRepo}";
        borg-info   = "env ${borgEnv} borg info ${borgRepo}";
        borg-check  = "env ${borgEnv} borg check ${borgRepo}";
        borg-unlock = "env ${borgEnv} borg break-lock ${borgRepo}";

        # System rebuild (darwin-specific)
        nix-rebuild = "_d=$PWD; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd ~/git/nixos; git pull && sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin && { sw_vers -productVersion | grep -q '^15\\.' && sudo softwareupdate --install --recommended --no-scan 2>/dev/null || true; }; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd -; unset _d";
        nix-sync = "~/git/nixos/scripts/sync-nixos-hosts.sh";
        fw-check = "~/git/nixos/scripts/check-fw-updates.sh";
        host-status = "~/git/nixos/scripts/host-status.sh";

        # macOS-specific
        flush-dns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";

        # Single-window remote view of just the IDrive360 GUI, no VNC — attaches over SSH
        # to the idrive360-xpra seamless session on the nas01-backup VM (same alias as
        # latitude). Requires an xpra client — verify/install with `brew search xpra`
        # (not added to Brewfile here since the cask name couldn't be confirmed live).
        idrive-app = "xpra attach ssh://scott@nas01-backup.warthog-royal.ts.net/100";
        # Restart the IDrive360 agent service inside the nas01-backup VM (same alias as nas01/latitude)
        idrive-restart = "ssh scott@nas01-backup.warthog-royal.ts.net sudo systemctl restart idrive360cron";
      };
      initExtra = ''
        export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"

        # Source nix-darwin environment if present
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
      '';
    };

    zsh = {
      enable = true;
      history.size = 10000;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        # Basic (from shell-aliases.nix)
        wtf = "alias";
        clr = "clear";

        # Docker one-liners
        cyberchef = "docker run -d -p 8080:8080 humangod/cyberchef";

        # Tailscale SSH shortcuts
        nas01 = "tailscale ssh nas01";
        backup = "tailscale ssh nas01-backup";
        log01 = "tailscale ssh log01";
        pihole01 = "tailscale ssh pihole01";
        pihole02 = "tailscale ssh pihole02";
        slap = "tailscale ssh latitude";
        latitude = "tailscale ssh latitude";
        vm01 = "tailscale ssh vm01";
        OTworkstation = "tailscale ssh OTworkstation";
        otworkstation = "tailscale ssh OTworkstation";
        ot = "tailscale ssh OTworkstation";

        # Tailscale troubleshooting
        ts-status = "tailscale status";
        ts-up = "sudo tailscale up";
        ts-down = "sudo tailscale down";
        ts-netcheck = "tailscale netcheck";
        ts-ip = "tailscale ip";
        ts-peers = "tailscale status --peers";
        ts-debug = "tailscale debug";
        # Enabled features for a node: no arg = self, or pass a hostname for a peer
        ts-info = ''f(){ if [ -z "$1" ]; then tailscale status --json | jq '.Self | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry, SSH: ((.Capabilities // []) | any(. == "https://tailscale.com/cap/ssh"))}'; else out=$(tailscale status --json | jq --arg h "$1" '.Peer[] | select((.HostName|ascii_downcase) == ($h|ascii_downcase)) | {Host: .HostName, OS, Tags, ExitNodeOption, Routes: .PrimaryRoutes, Relay, Online, KeyExpiry}'); if [ -z "$out" ]; then echo "ts-info: no peer matching '$1'" >&2; else echo "$out"; fi; fi; }; f'';

        # Grep with color
        gpc = "grep --color=always";

        # Git shortcuts
        g = "git";
        gs = "git status";
        ga = "git add";
        gaa = "git add -A";
        gc = "git commit";
        gcm = "git commit -m";
        gp = "git push";
        gpl = "git pull";
        gd = "git diff";
        gdc = "git diff --cached";
        gl = "git log --oneline --graph --decorate";
        gla = "git log --oneline --graph --decorate --all";
        gco = "git checkout";
        gb = "git branch";
        gba = "git branch -a";
        gf = "git fetch";
        gr = "git restore";
        grs = "git restore --staged";

        # Nix shortcuts
        nixdir = "cd ~/git/nixos";
        nix-update = "nix flake update";

        # Common utilities
        ll = "ls -lah";
        la = "ls -A";
        l = "ls -CF";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Kubernetes
        k = "kubectl";

        # URL encoding/decoding
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        # Tmux shortcuts
        t = "tmux attach-session -t default 2>/dev/null || tmux new-session -s default";
        tls = "tmux list-sessions";
        tn = "tmux new-session -s";
        ta = "tmux attach-session -t";
        tk = "tmux kill-session -t";

        # Borg backup (darwin - uses launchd instead of systemd)
        borg-status = "sudo launchctl list com.local.borg-backup";
        borg-logs   = "tail -100 $HOME/.local/share/borg/backup.log";
        borg-run    = "sudo launchctl start com.local.borg-backup";
        borg-list   = "env ${borgEnv} borg list ${borgRepo}";
        borg-info   = "env ${borgEnv} borg info ${borgRepo}";
        borg-check  = "env ${borgEnv} borg check ${borgRepo}";
        borg-unlock = "env ${borgEnv} borg break-lock ${borgRepo}";

        # System rebuild (darwin-specific)
        nix-rebuild = "_d=$PWD; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd ~/git/nixos; git pull && sudo darwin-rebuild switch --flake ~/git/nixos#airbook-darwin && { sw_vers -productVersion | grep -q '^15\\.' && sudo softwareupdate --install --recommended --no-scan 2>/dev/null || true; }; [ \"$_d\" != \"$HOME/git/nixos\" ] && cd -; unset _d";
        nix-sync = "~/git/nixos/scripts/sync-nixos-hosts.sh";
        fw-check = "~/git/nixos/scripts/check-fw-updates.sh";
        host-status = "~/git/nixos/scripts/host-status.sh";

        # macOS-specific
        flush-dns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";

        # Single-window remote view of just the IDrive360 GUI, no VNC — attaches over SSH
        # to the idrive360-xpra seamless session on the nas01-backup VM (same alias as
        # latitude). Requires an xpra client — verify/install with `brew search xpra`
        # (not added to Brewfile here since the cask name couldn't be confirmed live).
        idrive-app = "xpra attach ssh://scott@nas01-backup.warthog-royal.ts.net/100";
        # Restart the IDrive360 agent service inside the nas01-backup VM (same alias as nas01/latitude)
        idrive-restart = "ssh scott@nas01-backup.warthog-royal.ts.net sudo systemctl restart idrive360cron";
      };
      initContent = ''
        export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      '';
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "Scott";
          email = "scott@example.com";  # Update with your email
        };
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
      };
    };

    jq.enable = true;

    # VSCode - plain install, extensions managed via Settings Sync (GitHub account)
    # This allows installing any marketplace extension without Nix store limitations
    vscode = {
      enable = true;
      package = pkgs.vscode;
      # Extensions installed via VS Code marketplace and synced via GitHub Settings Sync
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        add_newline = true;

        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_status"
          "$python"
          "$nix_shell"
          "$direnv"
          "$custom"
          "$sudo"
          "$cmd_duration"
          "$line_break"
          "$character"
        ];

        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
          style = "bold cyan";
        };

        git_branch = {
          symbol = " ";
          style = "bold purple";
        };

        git_status = {
          conflicted = "🏳";
          ahead = "⇡\${count}";
          behind = "⇣\${count}";
          diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
          untracked = "?\${count}";
          stashed = "$";
          modified = "!\${count}";
          staged = "+\${count}";
          renamed = "»\${count}";
          deleted = "✘\${count}";
          style = "bold red";
        };

        python = {
          symbol = " ";
          style = "yellow bold";
          pyenv_version_name = true;
        };

        nix_shell = {
          symbol = " ";
          format = "via [$symbol$state]($style) ";
          impure_msg = "";
          pure_msg = "pure";
        };

        direnv = {
          disabled = false;
          format = "[$symbol$loaded/$allowed]($style) ";
          symbol = "direnv ";
          style = "bold orange";
          allowed_msg = "allowed";
          denied_msg = "denied";
          loaded_msg = "loaded";
          unloaded_msg = "unloaded";
        };

        custom.tailscale = {
          command = "tailscale status >/dev/null 2>&1 && echo '✓' || echo '✗'";
          when = "command -v tailscale >/dev/null 2>&1";
          format = "[TS:$output](bold green) ";
          description = "Tailscale VPN status";
          ignore_timeout = true;
        };

        sudo = {
          # Disabled on macOS: checking sudo credential cache via /usr/bin/sudo is slow
          disabled = true;
        };

        cmd_duration = {
          min_time = 500;
          format = "took [$duration]($style) ";
          style = "bold yellow";
        };

        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
        };

        aws.disabled = true;
        azure.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = false;
      };
    };

    tmux = {
      enable = true;
      terminal = "screen-256color";
      historyLimit = 10000;
      keyMode = "vi";
      clock24 = true;
      extraConfig = ''
        # Enable mouse support
        set -g mouse on

        # Start windows and panes at 1, not 0
        set -g base-index 1
        setw -g pane-base-index 1

        # Renumber windows when one is closed
        set -g renumber-windows on

        # Better colors
        set -g default-terminal "screen-256color"
        set -ga terminal-overrides ",*256col*:Tc"

        # Status bar styling
        set -g status-style 'bg=#333333 fg=#ffffff'
        set -g status-left-length 40
        set -g status-right '%H:%M %d-%b-%y'

        # Easy splits with | and -
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"

        # Vim-style pane navigation
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
      '';
    };

    # SSH *client* config lives in ~/.ssh/config.d/home-manager.conf (see the
    # home.file entry below), NOT in ~/.ssh/config directly. If home-manager
    # owned ~/.ssh/config it would install it as a read-only nix-store symlink,
    # and tools that *write* to it — the VS Code Tailscale extension's
    # `openRemoteCode`, plain `ssh-copy-id`, etc. — fail with EACCES. Instead
    # the top-level ~/.ssh/config is a writable stub that `Include`s our managed
    # file (created by the writableSshConfig activation script).
    ssh.enable = false;
  };

  # Managed SSH client hosts — used for outbound git, borg (nas01), and
  # tailscale ssh. No sshd server on this box (removed 11ecf08). This file is
  # store-backed (read-only) and pulled in via `Include` from the writable
  # ~/.ssh/config stub, so `Host *` here still wins (Include sits at the top and
  # ssh takes the first value seen for each option).
  home.file.".ssh/config.d/home-manager.conf".text = ''
    Host *
      AddKeysToAgent yes
      IdentityFile ~/.ssh/id_ed25519

    Host nas01
      HostName nas01.warthog-royal.ts.net
      User scott

    Host latitude
      HostName latitude.warthog-royal.ts.net
      User scott

    Host github.com
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_ed25519_github
  '';

  # Ensure ~/.ssh/config is a *writable* real file (not a nix-store symlink)
  # that Includes the managed hosts above. Tools like the VS Code Tailscale
  # extension append their own Host/ProxyCommand blocks here; those survive
  # rebuilds because we only touch the file when the Include line is missing.
  home.activation.writableSshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.ssh/config"
    inc="Include config.d/home-manager.conf"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [ -L "$cfg" ] || [ ! -e "$cfg" ]; then
      # Missing, or a stale home-manager-owned symlink from a prior generation.
      rm -f "$cfg"
      printf '%s\n' "$inc" > "$cfg"
    elif ! grep -qxF "$inc" "$cfg"; then
      # Pre-existing writable config: prepend the Include if it's not there yet.
      printf '%s\n%s\n' "$inc" "$(cat "$cfg")" > "$cfg.hm-tmp"
      mv "$cfg.hm-tmp" "$cfg"
    fi
    chmod 600 "$cfg"
  '';

}
