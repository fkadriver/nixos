# Pi-hole Deployment: SD Image to Running Hardware

This guide covers deploying a Pi-hole NixOS SD image from `nix build` all the way
to a running headless Raspberry Pi. The process has two phases: bootstrap (first boot
with limited secrets) and finalize (add the Pi's age key, deploy real secrets).

## Overview

- **pihole01** — Pi 4B, static IP `192.168.10.10`
- **pihole02** — Pi 3B, static IP `192.168.10.11`
- Both use sops-nix for secrets. The age key is generated on first boot, so
  `pihole-ftl` (which needs `pihole/pwhash`) will not fully start until Phase 2.

---

## Phase 1: Build the SD Image

### 1a. Add pihole/pwhash placeholder to secrets.yaml

The sops-nix module validates that all referenced secrets exist at build time.
`pihole/pwhash` must exist in `secrets.yaml` or the build will fail.

```bash
sops secrets/secrets.yaml
```

Add a placeholder (sops encrypts on save):

```yaml
pihole:
    pwhash: placeholder
```

Save and exit. Commit the updated secrets.yaml.

### 1b. Build

```bash
# pihole02 (Pi 3B)
nix build .#nixosConfigurations.pihole02.config.system.build.sdImage

# pihole01 (Pi 4B)
nix build .#nixosConfigurations.pihole01.config.system.build.sdImage
```

The image lands in:

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

### 4c. Get the real pihole/pwhash

Pi-hole v6 uses a BALLOON-SHA256 hash (not bcrypt). Copy it from an existing
running Pi-hole (pihole01):

```bash
ssh scott@192.168.10.10 "sudo grep app_pwhash /etc/pihole/pihole.toml"
# webserver.api.app_pwhash = "$BALLOON-SHA256$v=1$..."
```

Copy the full value after the `=` sign (the `$BALLOON-SHA256$...` string).

Alternatively, set a new password on the Pi's web UI and then read the hash back:

```bash
ssh scott@192.168.10.11 "sudo grep app_pwhash /etc/pihole/pihole.toml"
```

### 4d. Update secrets.yaml with the real hash

Back on your build machine:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml   # re-encrypts for the new pihole age key
sops secrets/secrets.yaml             # replace placeholder with real hash
```

Update the `pihole.pwhash` value to the BALLOON-SHA256 hash from step 4c.

### 4e. Rebuild and deploy over SSH

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

### 4f. Commit the changes

```bash
git add .sops.yaml secrets/secrets.yaml
git commit -m "pihole02: add age key, set real pihole/pwhash"
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
to force the build to run on latitude over SSH loopback. Latitude's config enables
sshd on `127.0.0.1` for this purpose.

After rebuilding latitude (`sudo nixos-rebuild switch --flake .#latitude`):

```bash
sudo nixos-rebuild switch --flake .#pihole02 \
  --target-host scott@pihole02 \
  --build-host localhost
```

If latitude hasn't been rebuilt yet, use the 3-step manual process:

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

Fix is applied in `common.nix` via an ip rule that ensures local VLAN traffic
(192.168.0.0/20) always uses the main routing table. Stop/start Tailscale if
you experience this on a Pi that hasn't been rebuilt yet.

---

## Troubleshooting

### pihole-ftl fails to start

Check the EnvironmentFile:

```bash
sudo systemctl status pihole-ftl
journalctl -u pihole-ftl -n 50

# Is the sops secret decrypted?
ls -la /run/secrets/pihole/pwhash
ls -la /run/secrets-rendered/pihole-ftl-env
```

If the files don't exist, the Pi's age key isn't in `.sops.yaml` yet — repeat Phase 4.

### SSH unreachable after flash

- Confirm the Pi is plugged into the correct switch port
- The static IP `192.168.10.11` requires the build machine to be on the same
  subnet (or have a route to `192.168.10.0/24`)
- Try connecting a monitor — the console will show the boot log and any errors

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
