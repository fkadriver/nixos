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

### 1b. Every record has `bytes: 0, packets: 0`: needs the template

- **Since day one:** every sampled record from Nov 1, 3, 9 and 16, plus the
  live stream, has zero counters. All other fields decode correctly.
- **Diagnosis so far** (135-packet capture from 2026-11-16, hand-decoded):
  - Data flowset 256 has 57-byte records, matching FreeBSD `ng_netflow`'s
    IPv4 layout.
  - The real counters are at record offsets 16–23, as two 32-bit fields:
    packets, then bytes. For example `0x00000001_00000034` is 1 packet,
    52 bytes, a TCP SYN.
  - Offsets 24–31 are always zero. That's what goflow2 reports as bytes and
    packets.
  - So the template most likely labels the real counters with field IDs that
    goflow2's default mapping doesn't read as bytes and packets, and puts the
    standard IDs (`IN_BYTES`=1, `IN_PKTS`=2) on the zero field.
- **Blocker:** the capture missed the template. OPNsense resends it about
  every 10 minutes (goflow2 metric `nf_flowset_total{type="TemplateFlowSet"}`
  was 95 over about 16 h), and goflow2 has no HTTP endpoint that dumps its
  template cache.
- [ ] Capture only template packets (up to 15 minutes; sudo needs your password):

      ! ssh -t log01 "sudo timeout 900 tcpdump -i eno1 -c 2 -w /tmp/nf-tmpl.pcap 'udp port 2055 and udp[28:2] = 0'"

- [ ] Decode it to get the field types and lengths:
      `tshark -r nf-tmpl.pcap -d udp.port==2055,cflow -V`.
- [ ] Fix it, then confirm records show `bytes > 0`. Either:
  - add a goflow2 mapping file in the `goflow2-netflow` repo (mount it and
    pass `-mapping=/mapping.yaml`) that maps those field IDs to
    `bytes`/`packets`; or
  - switch OPNsense to IPFIX if its template uses standard IDs there.

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
