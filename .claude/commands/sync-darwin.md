# Sync darwin-airbook with daily-driver / 3d-printing

Review `modules/daily-driver.nix` and `modules/3d-printing.nix` for additions or changes that should be reflected in the darwin config (`hosts/airbook-darwin/default.nix` for packages/casks, `hosts/airbook-darwin/home.nix` for shell aliases and helper commands), then interactively offer to apply them.

## Steps

1. **Read the source files** — read all four files:
   - `modules/daily-driver.nix`
   - `modules/3d-printing.nix`
   - `hosts/airbook-darwin/default.nix`
   - `hosts/airbook-darwin/home.nix` — shell aliases and helper commands live here, not in `default.nix`

2. **Identify candidates** — find items in daily-driver / 3d-printing that are absent or out-of-date in the darwin config. Candidates are:
   - New packages in `environment.systemPackages`
   - New casks or brews referenced in comments (the darwin config mirrors casks manually)
   - New activation scripts
   - Option defaults that were changed (e.g. `my.printing.*`)
   - New modules imported into daily-driver that have a darwin-applicable equivalent
   - **New or changed `environment.shellAliases`** in daily-driver — compare against *both* `programs.bash.shellAliases` and `programs.zsh.shellAliases` in `home.nix`. An alias present in one shell but not the other is drift too; report it.
   - **New `writeShellScriptBin` helper commands** in daily-driver's `environment.systemPackages` (e.g. `idrive-status`) — these have no packaged equivalent on darwin and are mirrored as shell functions in `home.nix`. Compare the *script body*, not just the name: a helper that exists on both sides but whose logic has diverged is the drift this check is most likely to catch.

3. **Filter automatically** — silently skip anything that is Linux/NixOS-only. Do NOT surface these to the user:
   - NixOS services: `services.*`, `programs.nix-ld`, `programs.firefox`, `hardware.*`
   - udev rules, systemd/logind config
   - Packages that only build on Linux (check if the nixpkgs package has `meta.platforms` restricted to linux, or if the name is a well-known Linux-only tool): `gparted`, `usbimager`, `brightnessctl`, `xdotool`, `xbindkeys`, `solvespace` (has a macOS cask so surface it), `inkscape` (already a cask — skip)
   - Desktop environment modules: KDE, XFCE, plasma, anything in `laptop-kde.nix`, `laptop-xfce.nix`, `desktop-minimal.nix`
   - Anything already present in the darwin config (exact match by package name or cask name)
   - Aliases and helpers whose command only works on Linux — ones that run `systemctl`, `virsh`, `journalctl`, `nixos-rebuild` etc. *locally*. Note the distinction: an alias that **SSHes to another host** and runs those there (like the `idrive-*` shortcuts) is portable and **should** be surfaced.
   - Aliases whose darwin counterpart is deliberately different rather than missing — `nix-rebuild` is `darwin-rebuild` on airbook, not `nixos-rebuild`. Never "sync" these into agreement.

4. **Surface candidates interactively** — for each remaining candidate, use AskUserQuestion to present it with context:
   - What it is and what it does
   - How it would be added to the darwin config (system package, homebrew cask/brew, activation script, shell alias, or shell function)
   - Whether a Homebrew equivalent exists for GUI apps
   - For a helper whose logic has diverged, show both versions so the user can pick which one is correct — the darwin copy is not automatically the stale one

   Group related items into a single question when possible (e.g. "3 new CLI tools from daily-driver", "4 new idrive-* shortcuts").

5. **Apply accepted changes** — for each accepted item:
   - CLI tools / nix packages → add to `environment.systemPackages` in `hosts/airbook-darwin/default.nix`
   - GUI apps with a Homebrew cask → add to the `casks` list with a comment matching the style already in the file
   - Activation scripts → add alongside `openscadBosl2` and `orcaSettings`
   - Shell aliases → add to **both** `programs.bash.shellAliases` and `programs.zsh.shellAliases` in `home.nix`. These two blocks are near-duplicates; editing only one is the most common way this config drifts.
   - `writeShellScriptBin` helpers → define the body **once** as a binding in the `let` block at the top of `home.nix` (see `idriveStatusFn`), then interpolate it into both `programs.bash.initExtra` and `programs.zsh.initContent`. Translate the script to a shell function; keep the output identical to the NixOS version so the two stay comparable. Watch for `${` in the body — it needs escaping as `''${` inside a Nix string.
   - Keep formatting consistent with surrounding code

6. **Verify** — after edits, run `nix flake check --no-build` and report the result. If `home.nix` changed, also run `nix build .#darwinConfigurations.airbook-darwin.system --no-link` — `flake check` will not catch a broken shell function, since the rc files are only generated during the build. To confirm a synced helper actually behaves, source the generated rc and run it:

   ```bash
   p=$(nix build --no-link --print-out-paths \
     .#darwinConfigurations.airbook-darwin.config.home-manager.users.scott.home.activationPackage)
   grep -A15 '<helper-name>()' "$p"/home-files/.zshrc
   ```

## Darwin compatibility rules (reference)

| NixOS item | Darwin equivalent |
|---|---|
| `environment.systemPackages` pkg | Same pkg in darwin `environment.systemPackages` if cross-platform |
| `environment.shellAliases` | `programs.bash.shellAliases` **and** `programs.zsh.shellAliases` in `home.nix` (both) |
| `writeShellScriptBin` helper | Shell function in `home.nix`: body in the `let` block, wired into `programs.bash.initExtra` **and** `programs.zsh.initContent` |
| GUI app with nixpkgs package | Homebrew cask (prefer) or nixpkgs if no cask exists |
| `system.activationScripts` | `system.activationScripts` (works on darwin too) |
| `services.*` | `launchd.daemons` or homebrew service or skip |
| `programs.firefox.enable` | Already a cask — skip |
| `programs.nix-ld` | Not applicable on darwin — skip |
| `hardware.*` | Not applicable — skip |
| `services.udev.extraRules` | Not applicable — skip |
| `services.logind.*` | Not applicable — skip |

## Notes

- The darwin config installs 3D printing apps via Homebrew casks, not nixpkgs — when daily-driver enables a nixpkgs 3D app that's already a cask in darwin, skip it silently.
- `sweethome3d` is already a cask (`sweet-home3d`) — skip.
- `f3d` — check if a homebrew cask exists; if yes, add as cask; if no, add as nixpkg.
- Always use `AskUserQuestion` before making any edit. Never silently apply changes.

### Shell shortcuts

- Shell aliases and helper commands are the part of daily-driver most prone to silent drift, because darwin can't import NixOS modules — every one of them is a hand-maintained duplicate. There is no build error when the two sides disagree; the shortcut simply doesn't exist on airbook, or quietly behaves differently.
- The `idrive-*` IDrive360 shortcuts are the current example: `idrive-app` and `idrive-start`/`idrive-stop`/`idrive-restart` are aliases on both sides, and `idrive-status` is a `writeShellScriptBin` on NixOS mirrored as the `idriveStatusFn` shell function on darwin. `idrive-vm-*` is deliberately **nas01-only** — never sync it to airbook.
- Report drift in both directions. Something present on airbook but missing from daily-driver usually means it belongs in the shared module, and that is worth surfacing rather than ignoring.
