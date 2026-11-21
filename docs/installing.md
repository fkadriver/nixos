# Installing a host (staged install)

A fresh install happens in three stages. The installer ISO puts down only a
small base system, and the host's full config is built afterwards, once it
can reach the fleet's caches.

**Why staged:** the full desktop configs are 30+ GB, and anything that isn't
in the public binary cache (e.g. orca-slicer) gets compiled from source. On
the ISO that build runs in a ~4 GB RAM disk, with no Tailscale, no secrets and
no SSH keys, so it can't reach the nas01 cache proxy or fetch fleet-built
packages from peers. The airbook's first install (2026-11-21) died exactly
there. The bootstrap stage is ~4 GB, all from cache.nixos.org.

## Stage 1: install `<host>-bootstrap` from the ISO

1. Build and write the ISO (see CLAUDE.md), boot the host from it.
2. `/etc/nixos-install-helper.sh` lists the `<host>-bootstrap` configs first.
   Pick the host's one and its install disk (e.g. `nvme0n1` on the airbook).
3. Reboot into it. The install logs a sops decryption error: expected, the
   host's age key isn't enrolled yet.

`<host>-bootstrap` (generated in `flake.nix` from `bootstrapHardware`) is the
host's own `hardware.nix` plus `modules/bootstrap.nix`: `common`, `user-scott`,
Wi-Fi, Tailscale, sops-nix + Bitwarden, `distributed-builds`, and sshd on
loopback. It mounts the standard disko layout (`main_vg-root`, `NIXBOOT`)
regardless of what the host's `hardware.nix` says.

## Stage 2: join the tailnet (on the host)

Log in as `scott` (the console banner repeats these steps) and run:

```bash
bootstrap-join
```

It runs `tailscale up --ssh --advertise-tags=tag:device` and prints a login
URL to approve on another device. The tag gives the host the same tailnet
policy as the rest of the fleet, so latitude can SSH to it. It then prints the
host's sops age public key.

## Stage 3: enroll and build (on latitude)

```bash
~/git/nixos/scripts/enroll-host.sh <host>
```

It:
1. reads the host's age key (`/var/lib/sops-nix/key.pub`) and `/etc/ssh` host key
2. adds the age key to `.sops.yaml`, runs `sops updatekeys`, and pins the host
   key in `modules/distributed-builds.nix` (if the host is a peer)
3. commits and pushes (asks first unless `--yes`)
4. on the host: pulls `~/git/nixos`, rebuilds `<host>-bootstrap` so secrets
   decrypt and Bitwarden delivers `id_ed25519_legacy` (needed for peer
   substitution), then rebuilds the full `<host>` config, which now fetches
   from the nas01 cache proxy and fleet peers

Then reboot the host. Other hosts trust its new host key after their next
rebuild (`nix-sync --apply`).

`enroll-host.sh` refuses the full build if `<host>`'s config doesn't mount
`/dev/mapper/main_vg-root` and `/dev/disk/by-label/NIXBOOT`, since that
system wouldn't boot on the disko layout. As of 2026-11-21 that applies to
**latitude** (whole disk by UUID, no LVM) and **vm01** and **OTworkstation**
(`/boot` by UUID): fix their hardware config before reinstalling them, or use
`--no-build` to enroll keys only.

## Other notes

- **Full configs still work from the ISO** (they're listed after the
  bootstrap ones), but they build everything on the ISO.
- **New host:** add it to `nixosConfigurations`, `bootstrapHardware` and
  `diskoConfigurations` in `flake.nix`, and to `peers`/`hostKeys` in
  `distributed-builds.nix` (any placeholder ed25519 key; `enroll-host.sh`
  replaces it with the real one).
- **Reinstalling an existing host:** same flow. `enroll-host.sh` replaces its
  old age key and host key.
- **Syncthing:** a reinstall generates a new device ID; update `deviceIds` in
  `modules/syncthing-declarative.nix`.
