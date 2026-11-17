# TODO

Open items from the 2026-11-16 full-repo review. Fixes already made in that
review are in commits `476dab5` and `ff3d200`.

## 0. Deploy the 2026-11-16 fixes

- [ ] latitude: `sudo nixos-rebuild switch --flake .#latitude` (mostly cache
      downloads now that the openldap overlay is gone), then restart Claude
      Code so it picks up mcp-nixos from `~/.claude.json`. Check with
      `claude mcp list`.
- [ ] Other NixOS hosts: `nix-sync`.

## 1. NetFlow on log01 (OPNsense → goflow2 → Wazuh): broken

OPNsense (`192.168.10.1`) exports NetFlow v9 to log01 UDP 2055, and goflow2
(`~/git/goflow2-netflow` on log01, run by `goflow2-docker.service`) decodes
it. Two separate faults mean Wazuh gets almost nothing useful.

### 1a. logrotate cuts goflow2 off every night: fix known, not applied

- **Cause:** the `remote-logs` logrotate rule in `hosts/log01/default.nix`
  covers `/var/log/remote/*/*.log`, including
  `OPNsense.internal/netflow.log`. It renames and compresses the file and
  sends a reload signal to rsyslog only. goflow2 keeps its file descriptor
  open on the deleted file, so `netflow.log` is gone and Wazuh has nothing to
  tail until goflow2 restarts. That's why a `netflow.log-*.gz` exists only for
  days after a restart (Nov 1, 2, 3, 5, 9, 15, 16).
- **Evidence (2026-11-16):** `docker exec goflow2 ls -l /proc/1/fd` showed
  `3 -> /out/netflow.log-20261116 (deleted)`, 710 MB and growing about
  1.1 GB/day. That space stays used until the container restarts.
- [x] Add `copytruncate = true;` to `services.logrotate.settings.remote-logs`.
      This is safe: goflow2 opens the file with `O_APPEND` (`fdinfo` flags
      `02102001`), and so does rsyslog.
- [x] Then run `docker restart goflow2` once on log01, to get a live
      `netflow.log` back and free the deleted file's space.
- [ ] Afterwards, confirm netflow events show up in Wazuh (rule 100500 in
      `wazuh-tailscale`'s `netflow-rules.xml`).

### 1b. Every record has `bytes: 0, packets: 0`: root cause found, fix applied

- **Root cause (2026-11-16, template capture decoded with tshark):** OPNsense's
  v9 templates (256 IPv4, 259 IPv6) are standard: `IN_PKTS`(2)/`IN_BYTES`(1)
  at record offsets 16–23 hold the real counters, then
  `OUT_PKTS`(24)/`OUT_BYTES`(23) at 24–31, which are always 0. goflow2
  (`producer/proto/producer_nf.go`) decodes **both** pairs into the same
  `Bytes`/`Packets` fields, so the trailing zeros overwrite the real values.
- A mapping can't suppress that overwrite (the default switch still runs
  after `MapCustomNetFlow`). So the fix copies fields 1/2 into custom protobuf
  fields `in_bytes`/`in_packets` (index 1001/1002) and renames them to
  `bytes`/`packets` on output, leaving the native ones out of
  `formatter.fields`. Wazuh rule 100500 needs no change.
- [x] `mapping.yaml` added to `~/git/goflow2-netflow` on log01, mounted
      read-only and passed as `-mapping=/mapping.yaml` in `docker-compose.yml`.
      Note: `formatter.fields` is a whitelist, so the always-empty keys (MACs,
      VLANs, MPLS, AS path, …) are now dropped from the JSON.
- [ ] Confirm in Wazuh Discover that netflow events show non-zero bytes.
- [ ] Optional: report upstream. goflow2 shouldn't let `OUT_*` clobber `IN_*`
      when a template carries both.

### 1c. Related

- [ ] `goflow2-netflow` on log01 is `git init`'d with files staged, but has no
      commits and no remote. Commit it, create a private GitHub repo, and push.
- [ ] log01's root disk is at 89% (91 of 108 GB on 2026-11-16). Find what's
      using it. Likely the Wazuh indexer, made worse by the deleted netflow
      file in 1a.

## 2. Infrastructure

- [ ] **pihole01:** `nix-community/raspberry-pi-nix` is archived upstream
      (last push 2025-03). Plan a migration to `nvmd/nixos-raspberrypi`. It
      has a binary cache, which should end the 1–2 day emulated kernel builds
      and the libbpf patch. This involves the kernel lock
      (`pihole.lockedKernelVersion`, plus `LOCKED_KERNEL_VERSIONS` in
      `scripts/deploy-piholes.sh`), the deploy script, and on-device testing.
      Do it as its own session.
- [ ] **Tether:** upstream `nix/module.nix:109` still sets
      `services.avahi.publish.{enable,userServices}`. That's the one eval
      warning left on latitude. Open an issue or PR on zackb/tether.

## 3. Dead and unused code

- [ ] `modules/desktop-minimal.nix`: no host imports it. Archive or delete it,
      and remove it from CLAUDE.md.
- [ ] `modules/dnclient.nix` / `modules/nebula.nix`: unused while the Nebula
      migration is paused. Consider moving them to `archive/` (resume path is
      in `docs/nebula.md`).
- [ ] **nas01**, leftovers from the decommissioned nas01-backup VM:
  - `virtualisation.libvirtd`;
  - `cloud-utils`;
  - the borg job's `after`/`wants` on `libvirtd.service`;
  - `LIBVIRT_DEFAULT_URI` in bash `initExtra`;
  - `hosts/nas01/nas01-backup-{domain.xml,setup.sh,vm-restore.sh}`
    (`setup.sh` doesn't even parse under shellcheck);
  - the commented `environment.etc` lines.

  Everything stays in git history.
- [ ] **nas01:** the `immich` user still has a login shell and the `docker`
      group, which is root-equivalent. The containers moved to vm01, so it only
      needs to own `/pool/photos` (uid 991, gid 989).
- [ ] **vm01:** remove the one-time `wazuhFreshInstall` / `wazuhReEnroll`
      activation scripts from the 4.14.5 migration (marker
      `/var/ossec/etc/.fresh-install-4145`).
- [ ] `MIGRATION-STEPS.md`: that Bitwarden migration is finished. Delete it.
- [ ] `scripts/sync-nixos-hosts.sh`: the `airbook` branches are dead, since
      airbook isn't in `HOSTS`.
- [ ] Sweet Home 3D is installed twice: `3d-printing.nix` (`pkgs`) and
      `home-design.nix` (`pkgsNixos`). Keep only the `home-design.nix` one.
- [ ] `font.nix` / `3d-printing.nix`: the `if pkgs ? "x" then ...` guards are
      all true on current nixpkgs. Simplify them to plain lists.
- [ ] `printing.nix`: `extraConf` holds only a comment. `cups-pdf-to-pdf` is
      installed but never configured. `gutenprint`/`gutenprintBin` do nothing
      for the Canon LBP162 laser.

## 4. Replacements and version bumps

- [ ] `modules/herdr.nix`: `pkgs.herdr` is now in nixpkgs (same 0.9.5, cached).
      Drop the hand-rolled fetch.
- [ ] `hddtemp` in `common.nix`: unmaintained since 2008. Use the `drivetemp`
      kernel module with `sensors`, or `smartctl -A`.
- [ ] LAN-Orangutan 3.3.8 → 3.4.2 (`common.nix`). Update both hashes.
- [ ] wtfi2 0.6.0 → 0.10.0 (`hosts/latitude/default.nix`).
- [ ] `font.nix`: Great Vibes, Allura and Parisienne are fetched from a moving
      `github.com/google/fonts/raw/main` URL with a fixed hash, so they'll
      break when those files change. Use
      `google-fonts.override { fonts = [ ... ]; }`. The dafont downloads have
      the same moving-URL risk.
- [ ] `font.nix`: re-check `font-manager`. Still not in the binary cache on
      2026-11-16, so presumably still failing to build.
- [ ] `printing.nix`: try `model = "everywhere"` (IPP Everywhere) for the
      LBP162 instead of the generic PostScript driver
      (`drv:///sample.drv/generic.ppd`), if it supports AirPrint.
- [ ] `borg-backup.nix`: replace the `lib.recursiveUpdate { ... } (optionalAttrs ...)`
      merge with `mkMerge [ ... ]`, the standard way to combine module config.

## 5. Small bugs and hardening

- [ ] `esphome-flash.nix`: the error message says it expects a CH340
      (`1a86:7523`), but the udev rules match FTDI (`0403:6001`, M5Stack) and
      Espressif (`303a:1001`).
- [ ] `forscan.nix`: the FTDI `0403:6001` rule also matches the M5Stack Atom,
      so it gets `/dev/obdlink-ex` too. Exclude `ATTRS{product}=="M5stack"`.
- [ ] **nas01 exports:** `/home/scott/git/idrive360` is exported
      `rw,no_root_squash` to sands-bak01, so root there can write anything as
      root. sands-bak01 only reads it, so use `ro` (and `root_squash` if
      possible).
- [ ] `distributed-builds.nix` and the latitude/vm01 `Host localhost` blocks
      set `StrictHostKeyChecking no`. Pin host keys with
      `programs.ssh.knownHosts`, as `borg-backup.nix` already does for nas01.
- [ ] `laptop-kde.nix` `kdeShortcuts`: the `command -v` check on a store path
      is always true, and `mkdir -p /home/scott/.config` as root can leave it
      root-owned on a fresh install.
- [ ] `docs/adding-hosts.md`: `nixos.wiki` → `wiki.nixos.org`.
