# Pi-hole Deployment: SD Image to Running Hardware

This guide covers deploying a Pi-hole NixOS SD image from `nix build` all the way
to a running headless Raspberry Pi. The process has two phases: bootstrap (first boot
with limited secrets) and finalize (add the Pi's age key, deploy real secrets).

## Overview

- **pihole01** — Pi 4B, static IP `192.168.10.10`
- **pihole02** — Pi 3B, static IP `192.168.10.11`
- Both use sops-nix for secrets (Bitwarden credentials). The Pi's age key is generated
  on first boot and must be added to `.sops.yaml` before secrets can be decrypted.
- The Pi-hole web UI password is fetched from Bitwarden at boot (the "Pi-Hole" item's
  password field holds the **plaintext** password). `pihole-set-password.service` calls
  `pihole-FTL --config webserver.api.password` which hashes it with BALLOON-SHA256 and
  writes the result to `pwhash` in `/etc/pihole/pihole.toml` before `pihole-ftl` starts.

---

## Phase 1: Build the SD Image

### 1a. Build

Using the deploy script (preferred — locks the kernel version check and out-links
each image separately so building both doesn't clobber the other's `result` symlink):

```bash
./scripts/deploy-piholes.sh --build-image                  # both Pis
./scripts/deploy-piholes.sh pihole01 --build-image          # pihole01 only
./scripts/deploy-piholes.sh pihole02 --build-image --verbose
```

Or manually:

```bash
# pihole02 (Pi 3B)
nix build .#nixosConfigurations.pihole02.config.system.build.sdImage

# pihole01 (Pi 4B)
nix build .#nixosConfigurations.pihole01.config.system.build.sdImage
```

The image lands in (`result-<host>-sdimage/` when built via the script,
`result/` when built manually):

```
result/sd-image/nixos-image-pihole02-aarch64-linux.img
result/sd-image/nixos-image-pihole01-aarch64-linux.img
```

---

## Phase 2: Flash the SD Card

Find your SD card device (check `lsblk` before and after inserting):

```bash
lsblk
```

Flash (replace `/dev/sdX` with your device — double-check before running):

```bash
sudo dd \
  if=result/sd-image/nixos-image-pihole02-aarch64-linux.img \
  of=/dev/sdX \
  bs=4M status=progress conv=fsync
sync
```

Eject the card and insert it into the Pi.

---

## Phase 3: First Boot

Connect the Pi to your switch via ethernet. Power it on.

The Pi will:
- Assign itself `192.168.10.10` (pihole01) or `192.168.10.11` (pihole02)
- Generate a fresh age key at `/var/lib/sops-nix/key.txt`
- Fail to start `pihole-ftl` — expected, because the `pihole/pwhash` secret
  cannot be decrypted yet (the Pi's age key isn't in `.sops.yaml`)

### Verify SSH access

```bash
ssh scott@192.168.10.11   # pihole02
ssh scott@192.168.10.10   # pihole01
```

If SSH is refused, wait ~60 seconds for boot to complete. If unreachable,
check that the Pi is on the right VLAN/switch and the gateway is correct in
`hosts/pihole0x/default.nix`.

---

## Phase 4: Bootstrap Secrets (First Time Only)

Do this once per Pi — it permanently registers the Pi's identity.

> **DNS note:** On first boot, `pihole-ftl` can't start because the sops secret
> isn't decrypted yet, so `127.0.0.1` (the primary nameserver) isn't listening.
> If you need to run any command on the Pi that requires DNS before completing
> this phase, temporarily override resolv.conf:
> ```bash
> echo "nameserver 9.9.9.9" | sudo tee /etc/resolv.conf
> ```
> All rebuilds in this phase should be run **from your build machine** using
> `--target-host` (step 4e), which builds locally and deploys over SSH —
> the Pi never needs to reach GitHub itself.

### 4a. Get the Pi's age public key

sops-nix generates the age key automatically on first boot. Just read it back:

```bash
ssh scott@192.168.10.11 "sudo grep 'public key' /var/lib/sops-nix/key.txt"
# Output: # public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 4b. Add the key to .sops.yaml

Edit `.sops.yaml` and uncomment/fill in the Pi's entry:

```yaml
  - &pihole02 age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

And add it to the `creation_rules` key group:

```yaml
          - *pihole02
```

### 4c. Rebuild and deploy over SSH

No reflash needed — push the updated config directly. The Pi's nix daemon
rejects unsigned store paths by default, but `pihole.nix` sets
`nix.settings.require-sigs = false`. On **first deploy**, this setting isn't
active yet, so you need a one-time workaround to break the read-only nix.conf
symlink on the Pi before copying:

```bash
# Step 1 — Allow unsigned paths on the Pi (first deploy only)
ssh -t scott@192.168.10.11 "sudo rm /etc/nix/nix.conf && \
  sudo sh -c 'cat /etc/static/nix/nix.conf > /etc/nix/nix.conf' && \
  echo 'require-sigs = false' | sudo tee -a /etc/nix/nix.conf && \
  sudo systemctl restart nix-daemon"

# Step 2 — Build locally (--no-sandbox required for QEMU binfmt aarch64)
nix build --no-sandbox .#nixosConfigurations.pihole02.config.system.build.toplevel

# Step 3 — Copy closure to Pi
nix copy --no-check-sigs --to ssh://scott@192.168.10.11 $(readlink result)

# Step 4 — Activate
ssh -t scott@192.168.10.11 "sudo $(readlink result)/bin/switch-to-configuration switch"
```

After this deploy, `require-sigs = false` is baked into the NixOS config and
subsequent deploys work without the workaround (see Subsequent Updates below).

`pihole-ftl` will start successfully once it can decrypt `pihole/pwhash`.

### 4d. Commit the changes

```bash
git add .sops.yaml secrets/secrets.yaml
git commit -m "pihole02: add age key"
git push
```

---

## Phase 5: Verify

```bash
# Check Pi-hole service (pihole-web doesn't exist in v6 — web UI is built into FTL)
ssh scott@192.168.10.11 systemctl status pihole-ftl

# Check DNS from your build machine (dig is not installed on the Pi)
dig @192.168.10.11 google.com +short

# Check firewall
ssh scott@192.168.10.11 "sudo nft list ruleset | grep -E '80|443|53'"

# Check Tailscale connected
ssh scott@192.168.10.11 tailscale status

# Web UI (from your laptop, on same network)
# http://192.168.10.11
```

---

## Subsequent Updates

`nixos-rebuild --target-host` by default builds on the target host (the Pi). The Pi
lacks kernel namespace support for sandboxing, so `--build-host localhost` is required
to force the build to run locally over SSH loopback.

Both **latitude** and **vm01** have sshd on `127.0.0.1` configured for this purpose.

> **Note:** `scott@pihole01`/`scott@pihole02` resolve via Tailscale MagicDNS to the
> Pi's tailnet address, not its LAN static IP. If Tailscale is down or unreachable,
> this hangs with "Connection timed out" even though the Pi is up — see
> [Troubleshooting](#nixos-rebuild---target-host-scottpihole0x-hangs-with-connection-timed-out)
> for using the static LAN IP instead.

### Using the deploy script (preferred)

From latitude or vm01:

```bash
./scripts/deploy-piholes.sh
```

The script:
- Auto-detects the available build host (vm01 first, then localhost)
- **Checks the kernel version** before building — warns and prompts if the kernel
  has changed from the locked version (a full kernel recompile takes ~2 hours)
- Deploys pihole01 then pihole02 sequentially
- Creates a GC root after each deploy so the compiled kernel is not garbage collected

### Kernel version locking

Each Pi uses a different kernel (Pi 4B via raspberry-pi-nix, Pi 3B via nixos-hardware).
The locked versions are declared in two places that must be kept in sync:

| Location | pihole01 | pihole02 |
|---|---|---|
| `hosts/pihole01/default.nix` | `pihole.lockedKernelVersion = "6.6.51"` | — |
| `hosts/pihole02/default.nix` | — | `pihole.lockedKernelVersion = "6.12.47-stable_20250916"` |
| `scripts/deploy-piholes.sh` | `LOCKED_KERNEL_VERSIONS[pihole01]` | `LOCKED_KERNEL_VERSIONS[pihole02]` |

The NixOS build will **fail with a clear message** if the actual kernel drifts from the
locked value (e.g. after `nix flake update`). To intentionally upgrade:
1. Update `pihole.lockedKernelVersion` in the host's `default.nix`
2. Update `LOCKED_KERNEL_VERSIONS` in `scripts/deploy-piholes.sh`
3. Run the deploy script — it will prompt for confirmation before the long recompile

### Manual deploy

```bash
sudo nixos-rebuild switch --flake .#pihole02 \
  --target-host scott@pihole02 \
  --build-host localhost \
  --sudo \
  --print-build-logs \
  --option builders ''
```

> **Note:** `--option builders ''` disables distributed builds. Without it, latitude
> and vm01 deadlock by farming derivations to each other in a cycle.

### Pre-seeding vm01's nix store (avoids recompilation)

If latitude has already built the Pi closures, copy them to vm01 before running the
deploy script there — it will find the paths in the local store and skip the aarch64
QEMU compilation entirely:

```bash
# Run on latitude
nix copy --to ssh://scott@vm01 \
  $(nix build .#nixosConfigurations.pihole01.config.system.build.toplevel --no-link --print-out-paths)
nix copy --to ssh://scott@vm01 \
  $(nix build .#nixosConfigurations.pihole02.config.system.build.toplevel --no-link --print-out-paths)
```

### Fallback: manual 3-step deploy

If `nixos-rebuild` is unavailable:

```bash
nix build --no-sandbox .#nixosConfigurations.pihole02.config.system.build.toplevel
nix copy --no-check-sigs --to ssh://scott@pihole02 $(readlink result)
ssh -t scott@pihole02 "sudo $(readlink result)/bin/switch-to-configuration switch"
```

---

## Tailscale Notes

### Web UI via Tailscale HTTPS

`pihole.nix` includes a `tailscale-serve-pihole` systemd service that automatically
runs `tailscale serve http://localhost:80` after Tailscale authenticates. This exposes
the Pi-hole web UI at `https://pihole0x.<tailnet>.ts.net` with a valid TLS cert —
no manual setup needed.

### Tailscale breaks LAN connectivity

If you use OPNsense (or any Tailscale subnet router) advertising your local VLANs,
the Pi will route local traffic through Tailscale instead of directly via eth0 when
`--accept-routes` is active. Symptoms: LAN SSH and web UI stop working while
Tailscale SSH still works.

Fix is applied in `pihole.nix` via an ip rule that ensures local VLAN traffic
(192.168.0.0/20) always uses the main routing table (piholes don't import
`common.nix` so the fix is repeated there directly). Stop/start Tailscale if
you experience this on a Pi that hasn't been rebuilt yet.

---

## Troubleshooting

### pihole-ftl fails to start

```bash
sudo systemctl status pihole-ftl pihole-set-password bitwarden-secrets-sync
journalctl -u pihole-ftl -u pihole-set-password -n 50

# Is the Bitwarden secret available?
sudo ls /run/bitwarden-secrets/
```

If `/run/bitwarden-secrets/` is empty, `bitwarden-secrets-sync` failed — check its
journal. The Pi's age key may not be in `.sops.yaml` yet (repeat Phase 4).

If `pihole-set-password` failed, check its journal for the error. Common causes:
- `readOnly = true` left in `/etc/pihole/pihole.toml` from a previous config
  (the service strips this automatically, but if it fails, remove it manually:
  `sudo sed -i '/readOnly.*=.*true/d' /etc/pihole/pihole.toml`)
- Bitwarden secret not yet available (service ordering issue — restart manually:
  `sudo systemctl restart pihole-set-password pihole-ftl`)

### Web UI shows no password prompt

`pwhash` in `/etc/pihole/pihole.toml` is empty or invalid:

```bash
sudo grep 'pwhash' /etc/pihole/pihole.toml
```

If `pwhash = ""`, `pihole-set-password` didn't run or failed. Check its status and
restart the service chain:

```bash
sudo systemctl restart pihole-set-password
sudo systemctl restart pihole-ftl
```

**Key: use `webserver.api.password`, not `webserver.api.pwhash`**

`pihole-FTL --config webserver.api.password "plaintext"` — accepts plaintext, hashes
with BALLOON-SHA256 (`$BALLOON-SHA256$v=1$s=1024,t=32$...`), writes result to `pwhash`.

`pihole-FTL --config webserver.api.pwhash "value"` — stores `value` raw (no hashing).
Storing plaintext here causes all logins to fail silently with "password incorrect"
because BALLOON(plaintext) ≠ plaintext.

`webserver.api.app_pwhash` is a separate randomly-generated app password — unrelated
to the main web UI login.

### SSH unreachable after flash

- Confirm the Pi is plugged into the correct switch port
- The static IP `192.168.10.11` requires the build machine to be on the same
  subnet (or have a route to `192.168.10.0/24`)
- Try connecting a monitor — the console will show the boot log and any errors

### `nixos-rebuild --target-host scott@pihole0x` hangs with "Connection timed out"

Symptom: SSH to the plain hostname (`ssh scott@pihole01`, or `nixos-rebuild ...
--target-host scott@pihole01`) times out, but the Pi is otherwise up and reachable.

Cause: `pihole01`/`pihole02` resolve via Tailscale MagicDNS
(`resolvectl query pihole01`) to the Pi's tailnet IP (e.g. `100.x.x.x`), which
takes priority over `/etc/hosts` or LAN DNS. If Tailscale on the Pi (or the
tailnet path between it and your build machine) isn't currently reachable, the
hostname resolves to a dead address even though the Pi answers fine on its LAN
static IP.

Fix: target the static LAN IP directly instead of the hostname:

```bash
nixos-rebuild boot --flake .#pihole01 --target-host scott@192.168.10.10 --sudo --option builders ''
```

### Gravity database stays empty / no blocklists after deploy or reboot

Symptom: `pihole-ftl` is `active`, but the web UI shows 0 domains on the
blocklist, and `pihole-ftl-setup.service` shows as `failed`:

```bash
sudo systemctl status pihole-ftl-setup
sudo journalctl -u pihole-ftl-setup -n 50
```

If the journal shows `kill: SIGRTMIN: invalid signal specification`, that's
this bug: the setup script (`modules/pihole.nix`) used to call bash's builtin
`kill -s SIGRTMIN <pid>` to notify FTL after seeding an empty gravity.db.
Bash's builtin `kill` doesn't know real-time signal names (and even external
`kill` binaries want `RTMIN`, not `SIGRTMIN`) — the builtin errors out, and
because the script runs under `set -e`, it aborts right there, before the
`addList` calls that populate the actual blocklists ever run.

Fixed by using `systemctl kill --signal=RTMIN --kill-whom=main
pihole-ftl.service` instead, which resolves the signal name correctly. If you
hit this on a Pi built from an older commit, redeploy with the current
`modules/pihole.nix` and reboot — gravity will repopulate on the next
`pihole-ftl-setup` run.

### rsyslog DNS logs not streaming in real time

DNS query logs (`/var/log/pihole/pihole.log`) are forwarded to log01 in real time via
rsyslog `imfile` in `inotify` mode — new entries are picked up immediately as Pi-hole
writes them.

To verify forwarding is active on a pihole:

```bash
sudo journalctl -u syslog -n 50
```

Look for `suspended` or `connection refused` warnings — these indicate log01 is
unreachable and messages are queueing locally (disk queue in `/var/spool/rsyslog/`).
When connectivity restores, queued messages flush automatically.

To watch live DNS queries arriving on log01:

```bash
tail -f /var/log/remote/pihole01/pihole-dns.log
```

### rsyslog warning: "parameter 'statefile' deprecated"

If you see this in the pihole journal:

```
error during parsing file .../syslog.conf: parameter 'statefile' deprecated but accepted
```

The `StateFile` parameter was removed from the imfile input in rsyslog v8.2512+. In
inotify mode, rsyslog manages file position state automatically. The fix is to remove
`StateFile` and `PersistStateInterval` from the imfile input in `modules/pihole.nix`
(already done as of commit b23e641).

---

### Cross-compilation fails on new package

Some packages fail to cross-compile for aarch64 due to nixpkgs bugs. Add them
to the overlay stub in `modules/pihole.nix`:

```nix
nixpkgs.overlays = [
  (final: prev: lib.optionalAttrs prev.stdenv.hostPlatform.isAarch64 {
    gh   = prev.runCommandLocal "gh-stub"   {} "mkdir -p $out";
    ncdu = prev.runCommandLocal "ncdu-stub" {} "mkdir -p $out";
    # add failing package here
  })
];
```
