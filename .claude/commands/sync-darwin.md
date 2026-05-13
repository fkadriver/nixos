# Sync darwin-airbook with daily-driver / 3d-printing

Review `modules/daily-driver.nix` and `modules/3d-printing.nix` for additions or changes that should be reflected in `hosts/airbook-darwin/default.nix`, then interactively offer to apply them.

## Steps

1. **Read the source files** — read all three files:
   - `modules/daily-driver.nix`
   - `modules/3d-printing.nix`
   - `hosts/airbook-darwin/default.nix`

2. **Identify candidates** — find items in daily-driver / 3d-printing that are absent or out-of-date in the darwin config. Candidates are:
   - New packages in `environment.systemPackages`
   - New casks or brews referenced in comments (the darwin config mirrors casks manually)
   - New activation scripts
   - Option defaults that were changed (e.g. `my.printing.*`)
   - New modules imported into daily-driver that have a darwin-applicable equivalent

3. **Filter automatically** — silently skip anything that is Linux/NixOS-only. Do NOT surface these to the user:
   - NixOS services: `services.*`, `programs.nix-ld`, `programs.firefox`, `hardware.*`
   - udev rules, systemd/logind config
   - Packages that only build on Linux (check if the nixpkgs package has `meta.platforms` restricted to linux, or if the name is a well-known Linux-only tool): `gparted`, `usbimager`, `brightnessctl`, `xdotool`, `xbindkeys`, `solvespace` (has a macOS cask so surface it), `inkscape` (already a cask — skip)
   - Desktop environment modules: KDE, XFCE, plasma, anything in `laptop-kde.nix`, `laptop-xfce.nix`, `desktop-minimal.nix`
   - Anything already present in the darwin config (exact match by package name or cask name)

4. **Surface candidates interactively** — for each remaining candidate, use AskUserQuestion to present it with context:
   - What it is and what it does
   - How it would be added to the darwin config (system package, homebrew cask/brew, or activation script)
   - Whether a Homebrew equivalent exists for GUI apps

   Group related items into a single question when possible (e.g. "3 new CLI tools from daily-driver").

5. **Apply accepted changes** — for each accepted item:
   - CLI tools / nix packages → add to `environment.systemPackages` in `hosts/airbook-darwin/default.nix`
   - GUI apps with a Homebrew cask → add to the `casks` list with a comment matching the style already in the file
   - Activation scripts → add alongside `openscadBosl2` and `orcaSettings`
   - Keep formatting consistent with surrounding code

6. **Verify** — after edits, run `nix flake check --no-build` and report the result.

## Darwin compatibility rules (reference)

| NixOS item | Darwin equivalent |
|---|---|
| `environment.systemPackages` pkg | Same pkg in darwin `environment.systemPackages` if cross-platform |
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
