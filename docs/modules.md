# NixOS Modules Reference

This document provides a high-level overview of all available modules in this repository.

## Core Modules

| Module | Description |
|--------|-------------|
| `common.nix` | Server-safe base configuration with CLI tools, tmux, git, docker, direnv, auditd, rsyslog forwarding to log01, logrotate (7-day). Imports `tailscale.nix` and `shell-aliases.nix` |
| `user-scott.nix` | User account configuration (wheel, networkmanager, docker groups). Passwordless sudo for `nixos-rebuild`, `nix`, `tailscale`, `borg`, `reboot` and `systemctl` — except `systemctl poweroff/halt/kexec`, which stay password-gated like shutdown/poweroff |
| `shell-aliases.nix` | System-wide shell aliases (`nas01`, `slap`, `log01`, `gpc`, rebuild commands), plus the `git-sync` command (`scripts/git-sync.sh`: pull every repo under `~/git` and print a report; also installed on airbook-darwin and, via `setup.sh`, sands-bak01). Fleet-management aliases (`nix-sync`, `fw-check`, `host-status`, `deploy-piholes`) live in `daily-driver.nix` / `deploy-pihole.nix` instead — see those entries |

## Desktop Environment Modules

| Module | Description |
|--------|-------------|
| `laptop-xfce.nix` | Full XFCE desktop with development tools, gaming support, media tools |
| `laptop-kde.nix` | Full KDE Plasma 6 with Windows 11-like taskbar, gaming, KDE Connect. Taskbar pins are declared in `desktop.kde.pinnedApps` (Konsole, Thunderbird, Dolphin, KRDC, Firefox, Ghostty by default; latitude and airbook). A `plasma-pinned-apps` user service writes them as `applications:<id>.desktop` at each Plasma login, which resets any pins changed in the GUI. Pinning from the GUI saves `/nix/store` paths, which stop working after GC. `[ ]` turns it off |
| `laptop-minimal.nix` | Minimal XFCE for testing (no WiFi auto-config, no Bitwarden) |
| `daily-driver.nix` | Shared configuration for Scott's daily-driver machines (applications, fonts, 3D printing). Also carries the `nix-sync`/`fw-check`/`host-status` fleet-management aliases and the IDrive360 client shortcuts (`idrive-app`, `idrive-start`/`stop`/`restart`, plus an `idrive-status` script and the `xpra` client they need — all point at `sands-bak01`, dedicated hardware, not a VM). Installs `herdr` (nixpkgs) for the `<host>-h` aliases (`herdr --remote <host>`), and Meta's `muse-code` terminal coding agent (`muse`; unfree). Also, for every daily driver (moved from latitude 2026-11-26): Tether (wireless iPhone bridge, replacing `iphone-usb`), the Wazuh agent plus `smart-monitor`/`disk-usage-monitor`, `mcp-nixos`, anki/geany/gimp/git-lfs/`wtfi2`, and Syncthing Tray preconfigured for the local host and nas01 (sops `syncthing_nas01_apikey`). geany is the default text editor via `mkDefault` (airbook-xfce keeps Mousepad). Thunderbird is installed but its accounts are not declared in Nix: the `tb-push` command (`scripts/tb-push.sh`) copies `~/.thunderbird` between daily drivers over Tailscale SSH, prompting for source/destinations and refusing while Thunderbird is running (or the host is unreachable) on any of them; each destination's old profile is moved to `~/.thunderbird.pre-tb-push-<time>`. Also the Home Assistant client side: `go-hass-agent` (community Linux companion agent — no official Linux client), its desktop entries, and a `systemd.user.services.go-hass-agent` unit that registers the agent at login with the sops token `home-assistant/agent_token` (skipped once `preferences.toml` has `registered = true`; inactive if the secret is missing). Imported via `laptop-kde.nix`/`laptop-xfce.nix` → latitude and airbook |

## Pi-hole Modules

| Module | Description |
|--------|-------------|
| `pihole.nix` | Pi-hole FTL + web UI, slim base config (replaces `common` for Pi hosts): tailscale, shell-aliases, git, vim, curl, wget, htop, tmux, starship, rsyslog forwarding to log01. Manages sops secrets for the admin password hash. DNS query logs (`/var/log/pihole/pihole.log`) are tailed in real time via rsyslog `imfile` (inotify mode) and streamed to log01 via TCP. FTL process logs (startup, errors) are sent to syslog via `misc.syslog = true`. |
| `deploy-pihole.nix` | Adds the `deploy-piholes` alias (`scripts/deploy-piholes.sh`). Imported only by `hosts/latitude` and `hosts/vm01` — the two machines actually used to build/deploy Pi-hole updates (vm01 is the aarch64 cross-build host, see `pi-builder.nix`/`distributed-builds.nix`) |

## Networking Modules

| Module | Description |
|--------|-------------|
| `tailscale.nix` | Tailscale VPN with firewall rules, DNS over TLS, DNSSEC. The paused Nebula replacement (`dnclient.nix`, `nebula.nix`) is in `archive/modules/`; see `docs/nebula.md` |
| `wireless.nix` | WiFi auto-connect for JEN_ACRES network (WPA-PSK) |

## Development Modules

| Module | Description |
|--------|-------------|
| `vscode.nix` | VSCode with extensions (Nix, Python, Docker, Claude Code) and gnome-keyring |
| `vscode-server.nix` | VS Code Server for Remote SSH with Claude Code CLI and nix-ld |

## Secrets & Security

| Module | Description |
|--------|-------------|
| `bitwarden.nix` | Generic Bitwarden/sops-nix secrets management module |
| `bitwarden-scott.nix` | Scott-specific Bitwarden SSH key deployment |
| `kali-docker.nix` | Headless Kali Linux (`kali-linux-headless`) in a Docker container via the `kali` wrapper command — NixOS counterpart to the archived airbook-darwin colima setup, minus the VM layer since the Docker daemon already runs natively. Imported by `daily-driver.nix`. See `docs/kali-docker.md` |

## Backup & Sync

| Module | Description |
|--------|-------------|
| `bootstrap.nix` | Stage-1 base system for staged installs (`<host>-bootstrap` in `flake.nix`): common, Tailscale, sops-nix + Bitwarden, distributed-builds, sshd on loopback, `bootstrap-join`. See `docs/installing.md` |
| `borg-backup.nix` | Encrypted Borg backups to remote servers via SSH |
| `syncthing.nix` | Basic Syncthing file sync service |
| `syncthing-declarative.nix` | Declarative Syncthing with predefined folders/devices |

## Hardware & Peripherals

| Module | Description |
|--------|-------------|
| `logitech.nix` | Logitech device support via Solaar, mouse button tools, NumLock on login |
| `multi-monitor.nix` | Autorandr profiles, custom lid switch handler for docking |
| `autorandr-profiles.nix` | Predefined autorandr display profiles |
| `iphone.nix` | iPhone integration (photo sync, file transfer, device management) |
| `printing.nix` | CUPS printing with Canon LBP162 and Avahi autodiscovery |

## 3D Printing & Design

| Module | Description |
|--------|-------------|
| `3d-printing.nix` | OrcaSlicer, FreeCAD, OpenSCAD, Blender, MeshLab, SolveSpace, f3d with optional font test generators |
| `home-design.nix` | Sweet Home 3D for interior design and floor plans, with plugin installer helper |
| `font.nix` | Modular font management (documents, craft, printing3d, nerd, viewer) |

## Disk & System

| Module | Description |
|--------|-------------|
| `disko-config.nix` | Automated disk partitioning (1GB boot + LVM with 8GB swap + root) |
| `virtualbox.nix` | VirtualBox host with extension pack |

## Vehicle Diagnostics

| Module | Description |
|--------|-------------|
| `forscan.nix` | FORScan (Ford/Lincoln/Mazda OBD-II tool) via Wine. Provides `forscan` command, udev rule for OBDLink EX (FTDI + STM32 variants), maps adapter to COM1 |

## Module Architecture

All modules use the **flakeContext** pattern:

```nix
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  # Module configuration
}
```

Modules are **auto-discovered** from the `modules/` directory - no need to register them in `flake.nix`. Import them in hosts via:

```nix
inputs.self.nixosModules.<module-name>
```

## Module Options

Some modules provide custom options:

### 3d-printing.nix
- `my.printing.enable` - Core 3D printing tools
- `my.printing.fonts.enable` - 3D-safe emboss fonts
- `my.printing.repairTools` - SVG/STL repair tools
- `my.printing.generateTestArtifacts` - Font test plate/keychain generators

### font.nix
- `my.fonts.documents` - Office/document fonts
- `my.fonts.craft` - Decorative/Cricut fonts
- `my.fonts.printing3d` - 3D printing optimized fonts
- `my.fonts.nerd` - Terminal fonts with Nerd Font glyphs
- `my.fonts.viewer` - Font management tools

### common.nix
- `logging.forwardToLog01` (bool, default `true`) — enable rsyslog TCP forwarding to `log01.warthog-royal.ts.net:514`. Set to `false` on log01 itself to prevent loops.

### borg-backup.nix
- Repository path, backup paths, exclusions
- Pruning schedule (daily, weekly, monthly retention)
- **sops-nix age key**: on hosts using sops-nix, the key's dir (`/var/lib/sops-nix`)
  is auto-added to `paths`, so a restored host can decrypt secrets without a new
  key + `sops updatekeys`
- Schedule configuration
- **Weekly restore verification** (`restoreTest`, on by default): a canary file is
  refreshed before every backup (its dir is auto-added to `paths`), and a weekly
  timer (`Sun 04:00`) deletes the live canary, restores it from the newest archive,
  verifies it, and puts it back. Results are logged to `/var/log/borg-restore.log`
  in a `borg_restore: status=OK|ERROR …` line and shipped to Wazuh via
  `services.wazuh-agent.extraLocalFiles`. Fully self-contained — enabling
  `services.borg-backup` on any host activates it automatically. The manager-side `borg_restore` decoder/rule
  lives in the `wazuh-tailscale` repo.
