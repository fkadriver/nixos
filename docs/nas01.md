# nas01 — NAS Server Reference

nas01 is a NixOS host (converted from Ubuntu in July 2026 after a permissions accident broke sudo/root). The entire system — ZFS, NFS, Syncthing, Borg server, Tailscale, IDrive360 — is declared in [hosts/nas01/default.nix](../hosts/nas01/default.nix).

The Ubuntu-era `apply.sh` deployment is archived at `archive/hosts/nas01-ubuntu/`.

## Hardware

- **Role**: NAS — file serving, Borg backup server, Syncthing hub, IDrive360 cloud backup
- **Model**: Dell PowerEdge T330 tower, service tag `86B3JH2` — migrated
  from an HP ProDesk 600 G4 Desktop Mini in August 2026 (retired; see
  [Hardware History](#hardware-history-hp-prodesk--dell-poweredge-t330-2026-08) below)
- **CPU**: Xeon E3-1270 v5 (4C/8T, 3.6GHz/4.0GHz turbo, 80W)
- **Memory**: 16GB 2133MHz ECC UDIMM, 2Rx8 (4 DIMM slots, 3 free — originally
  shipped 4x16GB=64GB per Dell's factory build sheet,
  [hosts/nas01/86B3JH2.csv](../hosts/nas01/86B3JH2.csv); expansion to 64GB
  deferred, 16GB has headroom for this workload)
- **Chassis**: 8x 3.5" hot-plug bay tower, dual 495W redundant PSU
- **Remote management**: iDRAC8 Enterprise (full remote KVM/virtual media)
- **Storage controller**: Dell HBA330 (true HBA passthrough, `mpt3sas`
  driver) — replaced the stock PERC H730 RAID-on-chip card so ZFS gets raw
  disk access
- **NICs**: Broadcom BCM5720, onboard dual-port 1GbE (`eno1`/`eno2`,
  `tg3` driver, confirmed via `ethtool -i eno1` 2026-08-22) — a second
  BCM5720 PCIe card is listed on the build sheet (4x 1GbE total) but hasn't
  shown up in `ip link` yet; unconfirmed whether it's installed
- **Tailscale hostname**: `nas01.warthog-royal.ts.net`
- Full Dell owner's manual: [docs/poweredge-t330-owners-manual.pdf](poweredge-t330-owners-manual.pdf)

### Drives

| Drive | Mount | Purpose |
|---|---|---|
| 500GB SATA HDD | `/` (LVM/ext4 via disko) | OS — single disk, not mirrored (a spare 1TB drive is kept as a cold spare instead; mdadm mirroring was considered and declined 2026-08-22) |
| 3x HGST HDS724040ALE640 4TB 7200rpm (RAIDZ1) | `/pool` | ZFS pool — NAS data + borg repos (lz4, ashift=12). Behind the HBA330; by-id paths still use the `ata-HGST_...` prefix, unchanged from the old controller |
| WD WD180EDGZ-11BLDS0 18TB 7200rpm | `/mnt/wd18t_1`, `/mnt/wd18t_3` | Functioning normally (confirmed 2026-08-22) — dropped off the SATA bus 2026-07, written off as failing at the time, but stress-tested clean under SpinRite and now mounted/serving with data intact. Mounts kept `nofail` as a precaution |

The ZFS pool and WD drive are **not** managed by disko — they carry data across OS reinstalls.

---

## Hardware History: HP ProDesk → Dell PowerEdge T330 (2026-08)

**Trigger**: the HP ProDesk's pool controller — an ASM1166 M.2-to-SATA
adapter card (the DIY trick used to give the Mini extra SATA ports) — failed
2026-08-12 (pool drives dropping offline / `zpool` hanging, not ZFS-reported
checksum errors — the 3x HGST drives themselves were intact). nas01 was
powered off and brought back up on the OS SSD alone; the pool was left
offline (NAS downtime accepted) until the replacement was built, rather than
risk import/export cycles on the flaky controller.

**Replacement**: Dell PowerEdge T330 tower, service tag `86B3JH2`, purchased
used on eBay 2026-08-04 for $249.99 — see the Hardware section above for
full specs. Went straight from the stock PERC H730 (RAID-on-chip) to a used
HBA330 (~$25–50, same PCIe slot/bracket family, same SAS cabling) rather
than running an interim RAID0-per-disk workaround on the H730 — true HBA
passthrough on day one.

**Timeline**:
- 2026-08-17: box physically arrived. Firmware badly out of date (BIOS
  2.0.8, all components dated 2017-04-08) — see
  [Firmware Update Log](#firmware-update-log-2026-08-18) below.
- 2026-08-18: firmware fully updated (bridge-update path required — see log).
- 2026-08-20: NixOS installed on a 500GB SATA HDD (not an SSD as originally
  planned — sourced/used what was on hand) via the installer USB; UEFI boot
  fixed after a Legacy→UEFI BIOS switch caused missing NVRAM entries — see
  [UEFI Boot Fix](#uefi-boot-fix-2026-08-20) below. `nas01-backup` VM
  recovered from the old ProDesk SSD via USB in the interim (pool still
  disconnected) — see
  [Troubleshooting](#recovering-the-nas01-backup-vm-from-an-old-os-disk-lvm-vg-name-collision).
- 2026-08-22: HBA330 installed, all drives reattached. ZFS pool
  auto-imported cleanly on boot (no manual `zpool import -f` needed —
  confirms hostId/pool metadata survived the move). `hd-idle`'s by-id paths
  needed **no changes** — the HGST serials kept their `ata-HGST_...` prefix
  even behind `mpt3sas` (the anticipated shift to `scsi-.../wwn-...` didn't
  happen). `hosts/nas01/hardware.nix` regenerated from real
  `nixos-generate-config --show-hardware-config` output and swapped in
  (confirmed `mpt3sas` is required — the boot disk is behind the HBA330
  backplane). The ProDesk's Intel e1000e Tx-hang workaround was removed
  from `default.nix` (confirmed wrong driver — `tg3`, not `e1000e`; no
  replacement mitigation added since `tg3` hasn't shown any hang symptoms).
  OS-disk mirroring was considered (mdadm, using a spare 1TB drive) and
  declined — kept as a cold spare instead.

**Burn-in**: `/etc/hw-burnin.sh` was run for the full 4-hour default duration
before going to production. Note it ran **before** the HBA330 and data
drives were installed — it soaked CPU/RAM and tested only the OS disk, so
it doesn't cover the HBA330, SAS backplane, or the 3x HGST/WD drives under
load. Consider a targeted re-test of those specifically if that coverage
ever matters (e.g. before trusting the pool under heavy write load).

**eno2**: explicitly disabled — `networking.networkmanager.unmanaged` (no
auto-DHCP if a cable is ever plugged in) plus a forced `ip link set eno2
down` in `networking.localCommands` (re-applied every network start, same
pattern used for one-off interface fixes elsewhere in this file).

### Firmware Update Log (2026-08-18)

**Why firmware wasn't actually the USB-boot blocker after all**: the T330
has an **IDSDM** (Internal Dual SD Module) — an SD card slot on the
external rear of the chassis near the USB ports — which the ancient BIOS
listed as its own bootable device independent of whatever was gating
external USB. Writing the NixOS installer ISO to an SD card and booting
from IDSDM sidestepped the "no USB boot option" problem entirely, without
needing any firmware update. Firmware was updated anyway afterward since
this unit is under an Allstate hardware warranty (not Dell ProSupport, so
no vendor firmware support available through it) and the goal was
everything current before standing up production.

**iDRAC access**: default `root` / `calvin` still worked (this generation
predates Dell's per-unit unique default password). iDRAC's SSH shell needs
a pseudo-terminal (`ssh -tt ...`) — piped one-shot commands without a pty
hang indefinitely. The iDRAC's own network port was initially cabled to a
separate, unrouted `192.168.254.0/24` out-of-band management VLAN; moving
it to the main `192.168.10.0/24` LAN made it reachable for the rest of
this process.

**The signature-verification wall, and the fix**: every update attempt
(F10 Lifecycle Controller network-share wizard, `racadm update` over CIFS)
initially failed with `RED007: Unable to verify Update Package signature`
— including via two completely different update code paths, which ruled
out a transport/tooling bug. Root cause: the iDRAC/LC firmware shipped on
this unit (2.43.43.43, dated 2017) predates Dell's currently-trusted
signing certificates. Dell documents the fix explicitly: **iDRAC updates
from below 2.70.70.70 must go through 2.70.70.70 first, then 2.82.82.82,
before jumping to current** — each step refreshes the LC's trusted-cert
store enough to validate the next. Bridged 2.43.43.43 → 2.70.70.70 (driver
`DNH17`) → 2.82.82.82 (`WGNHP`) → 2.86.86.86 (`VWF72`), each via `racadm
update`, each completing cleanly once on the right version. BIOS and all
other components validated fine afterward, confirming it was purely an
LC-side cert-trust gap, not anything wrong with the packages themselves.

**`racadm update` mechanics** (used for every component below, all via a
throwaway Samba container on vm01 — see conversation/session history for
the exact `docker run` incantation if recreating it):
- Single-file updates (`-f <file>`) only accept **CIFS or NFS** shares via
  `-l //host/share` — FTP (`-e`/`-t FTP`) is only for catalog-based
  (`Catalog.xml`) repository updates, not single files.
- Must be the **Windows-format DUP** (`.EXE`), even though nothing here
  runs Windows — the LC's out-of-band update engine only parses the
  Windows-wrapped package format. The Linux DUP (`.bin`) is for running
  directly on a live Linux OS instead (see steam-run note below).
- iDRAC8's embedded CIFS client needs the legacy **SMB1/NT1** dialect —
  modern Samba defaults to SMB2+, so the share needs `server min protocol
  = NT1` explicitly, or the iDRAC gets `RAC0904: remote file location not
  accessible`.
- The file must be the **correctly driver-ID-named** package
  (e.g. `..._VWF72_WN64_...`) — a generically-named file for the same
  version number got misclassified as job type "Generic" and rejected;
  the properly-named one worked immediately.
- BIOS/PERC/PSU/NIC updates land as **Scheduled (Start Time: Next
  Reboot)**, not applied immediately — trigger with `racadm serveraction
  powercycle`. iDRAC/LC firmware updates are the exception: they
  self-reboot the iDRAC automatically, no manual trigger needed.
- **PSU firmware specifically**: the system powers itself off for 3-10
  minutes mid-update as a normal part of the process — do not AC-cycle or
  unplug a cord during that window, or the PSU can end up in an
  unrecoverable state requiring an LC rollback.
- **NIC firmware must match the actual chipset**, not just "supports
  T330" in Dell's compatible-systems list — this unit's NICs are Broadcom
  **BCM5720** (confirmed via the factory build sheet), and three
  T330-compatible-but-wrong-chipset firmware files (Intel I350-family,
  Marvell/Broadcom-57800-family, Intel X710-family) all failed with
  `RED097: component not in target system inventory` before finding the
  correct one (driver `RG25N`, Broadcom NetXtreme firmware).
- Direct DUP downloads work via `curl` against Dell's CDN
  (`dl.dell.com/FOLDER.../<file>`) even though the JS-rendered product
  page (`www.dell.com/support/...`) 403s plain `curl` — useful if
  re-staging any of these later without a browser.
- Skipped: Dell's "Platform Specific Bootable ISO" (driver `HKW8G`) — it's
  dated December 2019, would likely *downgrade* BIOS/iDRAC from what's
  installed now, and doesn't publish a per-component version manifest.
  The `racadm`-per-component approach gave precise control instead.
- **Backplane firmware**: checked five different Dell backplane driver
  pages (`2F90T`, `X3JNV`, `VV85D`, `9WH0P`, `HRP1V`) — none list T330 as
  compatible. Very likely this chassis's 8-bay backplane is passive/dumb
  with no separately updatable firmware, unlike larger PowerEdge towers
  (T440/T640) with expander backplanes. Unresolved; check iDRAC's hardware
  inventory directly if this needs settling for certain later.

**Final firmware versions (as of 2026-08-18)**:

| Component | Version |
|---|---|
| BIOS | 2.20.0 |
| iDRAC / Lifecycle Controller | 2.86.86.86 |
| PERC H730 | 25.5.9.0001, A17 |
| PSU (Delta 495W) | 00.1B.83 |
| NIC (Broadcom BCM5720, onboard + add-in card) | 21.60.2 |

The H730 will still be pulled for the HBA330 swap per the plan above — it
was updated anyway since the user plans to sell or reuse the card later
and wanted it current first.

### UEFI Boot Fix (2026-08-20)

NixOS was installed on the T330's boot disk while BIOS was still in
Legacy/CSM mode, then BIOS was switched to native UEFI afterward. The box
booted, but POST showed several "Unable to find UEFI device at ..." errors.

Root cause: `bootctl`/systemd-boot's NixOS activation had written the loader
binaries to the ESP, but couldn't register EFI NVRAM boot variables while
booted under Legacy mode (no `/sys/firmware/efi` at install time) — so it
was booting only via the generic UEFI fallback path
(`\EFI\BOOT\BOOTX64.EFI`), with no real NVRAM boot entry
(`bootctl status` showed "No boot loaders listed in EFI Variables"). That's
what threw the stale-entry POST errors.

Fix — once actually booted in UEFI mode:
```bash
sudo bootctl install
```
This creates proper `Linux Boot Manager` / `Fallback Linux Boot Manager`
NVRAM entries. Clean up any stale entries afterward in BIOS (F2 → Boot
Settings → UEFI Boot Sequence). No reinstall/reformat needed — the GPT+ESP
layout from disko was already correct.

**Applies to any host**, not just nas01: if a NixOS box is installed while
BIOS is in Legacy mode and later switched to UEFI (or `bootctl status` ever
shows "No boot loaders listed in EFI Variables"), this is the fix.

### Post-Migration/Rebuild Verification Checklist

**Applies to any host**, not just nas01: a fresh OS install (new hardware,
reinstall, or disk replacement) regenerates several machine identities that
other hosts/services pin *by value*. The pool/data survives fine; it's the
cross-host trust relationships that silently break until each is re-pinned.
Check every item below, not just the ones that happen to error loudly —
several of these fail silent (stale cache, wrong log path, timing) rather
than throwing an obvious error.

1. **SSH host key** — changes on every fresh install. Anything that pins it
   declaratively (`programs.ssh.knownHosts` in `modules/borg-backup.nix` for
   nas01) needs the new key, then a rebuild on every host that has the pin.
   Also check **each client's own cached known_hosts** separately from the
   declarative pin — darwin's borg jobs use `StrictHostKeyChecking=accept-new`
   (not a pin), which only trusts *unseen* hosts; a stale cached entry still
   has to be removed by hand first (`ssh-keygen -R <host>`), and remember
   **root's known_hosts is a separate file from the user's**
   (`/var/root/.ssh/known_hosts` on darwin, `/root/.ssh/known_hosts` on
   Linux) — the user-level fix doesn't cover anything invoked via `sudo`.
   Get the real new key with `ssh-keyscan -t ed25519 <host>` and cross-check
   its fingerprint (`ssh-keygen -lf -`) against what the failing connection
   itself reports, rather than trusting either blind.
2. **Syncthing device ID** — regenerated on a fresh install (new cert).
   Declared in `modules/syncthing-declarative.nix`'s `deviceIds` map; every
   peer with the old ID hardcoded won't reconnect until it's updated *and*
   that peer is rebuilt. Pull the live value with the Syncthing REST API
   (`GET /rest/system/status`, field `myID`) or straight from
   `~/.config/syncthing/config.xml`'s `<device id=...>` entry for the host's
   own name.
3. **sops-nix age key** — normally regenerated fresh on a new install, which
   would require adding the new pubkey to `.sops.yaml` and
   `sops updatekeys`. If the old `/var/lib/sops-nix/key.txt` was deliberately
   restored from the previous box (as happened here), verify the restore
   actually took: `sudo age-keygen -y /var/lib/sops-nix/key.txt` on the box
   should match the existing `.sops.yaml` entry — if it does, no
   `updatekeys` needed; if it doesn't, treat it as a fresh key per above.
4. **ZFS pool import** — `networking.hostId` is declared in Nix, not
   hardware-derived, so it survives automatically as long as the same config
   is deployed — just confirm `zpool status` is clean (`ONLINE`, 0 errors,
   no unexpected resilver) rather than assuming it imported correctly.
5. **Disk by-id paths** — anything hardcoded (`hd-idle`, `fileSystems`,
   pool member paths) should be re-verified against `ls /dev/disk/by-id/`
   on the real hardware rather than assumed. A controller swap (RAID HBA →
   true HBA passthrough) *can* change the by-id prefix
   (`ata-...` → `scsi-...`/`wwn-...`) but doesn't always — confirm instead
   of guessing either way.
6. **Wazuh agent enrollment** — a fresh install gets a new agent identity;
   confirm it actually re-enrolled (`client.keys` non-empty,
   `journalctl -u wazuh-agent` free of repeated connect/enroll errors) not
   just that the service reports `active`. Then, on the manager, also
   confirm **group membership**: `agent_groups -s -i <id>` (or
   `-l -g <group>`) against *every* group in `agent_groups -l` whose
   criteria the host actually meets — not just the groups it used to
   belong to, since that assumes the pre-migration membership was
   complete (it wasn't, see below). Check each shared `agent.conf`'s own
   header comment for its intended host list (docker enabled? →
   `docker-hosts`; this specific host? → `nas01-health`) and cross-check
   against reality (`virtualisation.docker.enable`, etc.), not memory. A
   fresh enrollment always lands in `default` only — group membership is
   set server-side and does not carry over from the old agent identity,
   so any shared config tied to a non-default group (command pollers,
   extra localfiles, wodles, etc.) silently stops applying until the host
   is re-added with `agent_groups -a -i <id> -g <group>`. Found
   2026-08-30: nas01 sat in `default` only for over a week post-migration
   — both `nas01-health` (ZFS pool status poller) and `docker-hosts`
   (docker-listener wodle, despite `docker.enable=true` fleet-wide via
   `common.nix`) were missing; the latter had apparently never been added
   even before the migration.
7. **Borg backup jobs** — expect every repo to show `STALE` immediately
   after any outage/migration window (no completed backup during the
   downtime) — that's normal, not a fault. Confirm it clears after the next
   scheduled run actually completes (`status=OK`, not just that the timer
   fired), and separately run `borg check` against every repo at least once
   — a period of flaky hardware upstream of the pool (like the failing
   ASM1166 here) can put questionable data in a repo without the ordinary
   nightly `create`/`prune` path ever objecting.
8. **VM/container workloads** (e.g. the IDrive360 `nas01-backup` libvirt VM)
   — confirm running state, network reachability, and that whatever it
   backs up to externally is still actually receiving uploads, not just
   `virsh domstate` == running.
9. **File shares** (NFS) — confirm reachable from an **actual client**,
   not just `systemctl is-active`; a same-host loopback probe is not a
   reliable substitute and can fail on protocol negotiation even when the
   service is fine for real clients.
10. **Network interface names/drivers** — don't carry over
    hardware-specific workarounds (Tx-hang mitigations, driver-specific
    quirks) onto new hardware unverified; confirm the driver
    (`ethtool -i <iface>`) actually matches before assuming an old
    workaround still applies.
11. **Docs** — update the Hardware section (service tag, specs) and this
    doc's migration history once everything above is confirmed; remove any
    "in progress" language.

**nas01 T330 (2026-08-22) — result of running this checklist**: SSH host
key pin and Syncthing device ID were both stale (fixed — see the
`modules/borg-backup.nix` and `modules/syncthing-declarative.nix` commit
from this date); sops age key survived the restore intact (verified match,
no `updatekeys` needed); ZFS pool clean; `hd-idle` by-id paths needed no
changes; Wazuh agent re-enrolled cleanly; borg staleness across all 5 repos
was the expected outage artifact, not a new fault. `latitude`/`vm01`/`log01`
still need a rebuild to pick up the two fixed pins; airbook needs
`sudo ssh-keygen -R nas01.warthog-royal.ts.net` (root's known_hosts
specifically) plus a `darwin-rebuild switch`.

---

## Disaster Recovery — OS Disk Failure

nas01's OS disk (a 500GB SATA HDD, behind the HBA330 backplane — see
Hardware above) is a single, non-redundant drive; an mdadm mirror was
considered and declined 2026-08-22, kept as a cold spare instead. Everything
on the OS disk is either declarative (rebuildable from this flake) or backed
up to `/pool` (the redundant ZFS raidz1 array, which lives on three *other*
physical disks and survives an OS-disk failure untouched). The only things
that are **not** reproducible from git are `/home` and the `nas01-backup`
VM's disk — both are backed up nightly to `/pool/borg/nas01` (see
[Borg Backup](#borg-backup-server-side) below) specifically so this runbook
can restore them.

These same steps also apply to an intentional fresh install (e.g. a new OS
disk), not just a failure.

### 1. Partition OS disk and install (from NixOS installer USB)

```bash
# Identify the OS disk by-id (check `ls -la /dev/disk/by-id/` for the
# right one — exclude the by-id entries for the 3x HGST pool drives and
# the WD 18TB drive):
ls -la /dev/disk/by-id/

# Partition ONLY the OS disk (ZFS/WD drives untouched):
sudo nix run github:nix-community/disko -- --mode disko \
  --flake github:fkadriver/nixos#nas01 \
  --arg device '"/dev/disk/by-id/<os-disk-by-id-path>"'

sudo nixos-install --flake github:fkadriver/nixos#nas01
sudo reboot
```

### 2. sops age key (first boot)

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
# Replace the old nas01 key in .sops.yaml with this one, then:
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml
# Commit/push, then rebuild nas01
```

This step matters for recovery specifically because `/run/bitwarden-secrets/borg_passphrase`
(needed to read the Borg repo in steps 4–5 below) only appears after this key
is trusted and a rebuild has run.

### 3. Import the ZFS pool

```bash
sudo zpool import -f pool   # -f: pool wasn't cleanly exported from old OS
zpool status                # confirm raidz1-0 is ONLINE, no errors
```

`boot.zfs.extraPools` auto-imports the pool on subsequent boots.
`/pool/borg/nas01` (this host's own Borg repo — see below) and
`/pool/borg/<hostname>` for every client already exist on the pool and need
no re-creation; they came back with the import.

### 4. Restore `/home` from Borg

```bash
LATEST=$(sudo env BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" \
  borg list --last 1 --format '{archive}' /pool/borg/nas01)

cd / && sudo env BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" \
  borg extract "/pool/borg/nas01::$LATEST" home

# home-manager-managed dotfiles are restored as plain files (not the usual
# nix-store symlinks) — relink them:
sudo nixos-rebuild switch --flake ~/git/nixos#nas01
```

Syncthing itself will already be running by this point (it starts during
step 2's rebuild, with a freshly-generated identity). The `/home` extract
above overwrites `cert.pem`/`key.pem` in `/home/scott/.config/syncthing/`
with the old identity, so restart it to pick that up (keeps the old device
ID — no re-pairing needed):
```bash
sudo systemctl restart syncthing
```

### 5. Restore the nas01-backup VM disk

```bash
sudo bash /etc/nas01-backup/vm-restore.sh
```

Extracts the latest qcow2 + cloud-init ISO from `/pool/borg/nas01` and
defines + starts the VM (domain.xml is already back in place declaratively
from step 2's rebuild). Pass an archive name as an argument to restore a
specific point instead of the latest — list them with
`idrive-vm-list`. See [IDrive360](#idrive360-cloud-backup-qemukvm-vm) below
for details on what is/isn't captured.

### 6. Verify

```bash
zpool status                        # pool healthy
idrive-status                       # nas01-backup VM running
borg-repos                          # other hosts' repos visible under /pool/borg
```

---

## Ongoing Maintenance

```bash
sudo nixos-rebuild switch --flake ~/git/nixos#nas01
```

---

## Storage Layout

```
/pool/                      ZFS RAIDZ1 (3x 4TB HGST)
  data/                     Main NAS data — NFS export
  shares/                   SANS + photos NFS exports
  syncthing/                Syncthing folders (Documents, Downloads, Photos)
  borg/                     Borg backup repos: <hostname> per client

/mnt/wd18t_3/               WD 18TB drive — functioning normally (confirmed 2026-08-22)
```

---

## Services

All declared in [hosts/nas01/default.nix](../hosts/nas01/default.nix):

| Service | NixOS option | Notes |
|---|---|---|
| NFS | `services.nfs.server` | fixed ports 4000/4001/20048 for firewall |
| Syncthing | `services.syncthing-declarative` | Tailscale-only, device ID preserved |
| ZFS | `boot.zfs.extraPools` | weekly autoScrub + TRIM enabled |
| hd-idle | custom `systemd.services.hd-idle` | by-id paths; pool 30 min, WD 10 min spindown |
| smartd | `services.smartd` | drive health monitoring |
| Wazuh agent | `services.wazuh-agent` | manager: wazuh.warthog-royal.ts.net |
| rsyslog → log01 | `logging.forwardToLog01` (common.nix) | on by default |
| IDrive360 | `virtualisation.libvirtd` (nas01-backup VM) | see below |

---

## IDrive360 (cloud backup, QEMU/KVM VM)

IDrive360's installer self-updates and downloads its backup engine at runtime,
which is incompatible with Nix packaging. It runs in a persistent Ubuntu 24.04
QEMU/KVM VM named `nas01-backup` instead of a Docker container.

- **VM disk**: `/var/lib/libvirt/images/nas01-backup.qcow2` (20 GB, persists across reboots)
- **Data access**: `/pool` and `/mnt` mounted via virtiofs into the VM
- **Desktop**: LXDE on the guest's real console (`:0`), lightdm auto-logs in
  scott at boot with no password (`nopasswdlogin` group) — reached via QEMU's
  own console VNC, bound to nas01's tailscale IP (`idrive-console-vnc` alias),
  not an in-guest VNC server
- **VM definition**: `hosts/nas01/nas01-backup-domain.xml` deployed to `/etc/nas01-backup/domain.xml`
- **Setup script**: `hosts/nas01/nas01-backup-setup.sh` deployed to `/etc/nas01-backup/setup.sh`

One-time setup (already done — the VM is registered and running):
```bash
sudo bash /etc/nas01-backup/setup.sh
```

Useful aliases (available in scott's shell on nas01). Note the split: bare
`idrive-*` acts on the **idrive360cron agent inside the VM** (cheap, safe to
restart any time), while `idrive-vm-*` acts on the **VM itself** (virsh power
state and the VM-disk Borg backup):
```bash
idrive-status       # VM state + idrive360cron agent status inside the VM
idrive-start        # start the idrive360cron agent service inside the VM
idrive-stop         # stop it
idrive-restart      # restart it
idrive-ip           # virsh domifaddr nas01-backup
idrive-ssh          # ssh directly into the VM
idrive-console      # serial console (Ctrl+] to exit)

idrive-vm-start     # sudo virsh start nas01-backup
idrive-vm-stop      # sudo virsh shutdown nas01-backup
idrive-vm-restart   # graceful shutdown, wait, offer force-destroy, then start
idrive-vm-backup    # run the VM-disk Borg job now (borgbackup-job-system.service)
idrive-vm-list      # list archives in /pool/borg/nas01
idrive-vm-restore   # sudo bash /etc/nas01-backup/vm-restore.sh
```

The graphical console is QEMU's own, reachable over Tailscale without an SSH
tunnel at `nas01.warthog-royal.ts.net:5900` (no password) — connect from
whatever tailnet device you're sitting at, e.g. on latitude:
`krdc vnc://nas01.warthog-royal.ts.net:5900`.

**On client hosts** (latitude, airbook-darwin) the agent-level subset is
available — `idrive-start`/`idrive-stop`/`idrive-restart` (SSH to the VM) and
`idrive-app` (single-window xpra view of the IDrive360 GUI). airbook-darwin
also has `idrive-status`, which gets VM state via `virsh` over SSH on nas01
since it isn't the libvirt host; latitude doesn't have it yet. The
`idrive-vm-*` VM controls exist only on nas01.

### Monitoring (Wazuh agent inside the VM)

`nas01-backup` is a plain Ubuntu 24.04 guest, so it runs the **native** Wazuh
agent (standard `.deb` + systemd unit) rather than the NixOS FHS-wrapped
build `modules/wazuh-agent.nix` uses on real hosts — same manager
(`wazuh.warthog-royal.ts.net`), reached over the VM's normal NAT path (ports
1514/1515 are open through to the manager without needing Tailscale inside
the guest).

`nas01-backup-setup.sh`'s cloud-init installs the package and points it at
the manager automatically on a fresh VM build, but does **not** enroll it —
enrollment needs the live enrollment password, which isn't baked into the
cloud-init image for secrets-hygiene reasons. Enroll manually after first
boot (already done for the current VM):

```bash
sudo /var/ossec/bin/agent-auth -m wazuh.warthog-royal.ts.net -P '<password>' -A nas01-backup
sudo systemctl enable --now wazuh-agent
```

Password: same Bitwarden item as the host's own agent
(`wazuh_agent_enrollment_password` / "Wazuh Agent Enrollment"), readable on
nas01 at `/run/bitwarden-secrets/wazuh_agent_enrollment_password`.

Verify: `sudo /var/ossec/bin/wazuh-control status` inside the VM, or
`sudo grep -i connect /var/ossec/logs/ossec.log`.

#### IDrive360 backup status

The Docker-era setup had a host-side script that parsed IDrive360's status
file and wrote a synthetic syslog line for Wazuh to tail (removed in commit
b20740e — the VM's internal state isn't visible on the host filesystem the
way a Docker bind mount was). Now that the VM has its own Wazuh agent with
direct filesystem access to the real files, that workaround is unnecessary:
`ossec.conf` inside the VM has `<localfile>` entries (`log_format: json`)
pointing straight at IDrive360's own status files — pure passive monitoring,
nothing about the IDrive360 install itself is touched:

- `.userInfo/lastBackupStatus.txt` — `{status, filename, jobType}` of the last backup job
- `.userInfo/lastActivitystatus.txt` — current/last activity + its log path
- `.userInfo/lastOnlineBackupStatus.json` — last online backup, `{status, time}`

(Full path: `/opt/IDrive360/idriveIt/user_profile/scott/*/.userInfo/...` — the
profile-hash directory changes on re-registration, hence the glob.)

Known caveat (superseded — see below): these files are rewritten in place
on each update, not appended to. The original design assumed Wazuh's log
collector would at least catch growing rewrites and only miss same-length
ones. Live testing on 2026-07-28 showed it's worse than that: rewriting
`lastOnlineBackupStatus.json` — including a rewrite that grew the file from
39 to 95 bytes — went completely undetected, even across a fresh
`wazuh-agent` restart. Wazuh's file-tailing localfile monitor cannot be
trusted for status files IDrive360 overwrites in place.

Replaced with a command-based approach: `/usr/local/bin/wazuh-idrive360-status`
reads `lastOnlineBackupStatus.json` fresh on every run (no tailing, no
truncation-detection dependency) and Wazuh executes it every 15 min via a
`<localfile><log_format>command</log_format>` block — the same pattern
already used for `wazuh-borg-status`. Canonical source for the script,
decoder, and rules lives in the `wazuh-tailscale` repo:
`config/wazuh_cluster/scripts/idrive360-status.sh`,
`decoders/idrive360-command.xml`, `rules/idrive360-command-rules.xml`.

Baked into `nas01-backup-setup.sh`'s cloud-init
(`idrive360-wazuh-command.py`, idempotent) so a fresh VM build gets this
automatically — it patches `ossec.conf` right after the Wazuh package
install, before the (manual) enrollment step.

### VM disk backup and restore

The live qcow2 disk lives on the OS SSD (not the redundant `/pool`), so it's
backed up nightly to `/pool/borg/nas01` via `services.borg-backup` (same Borg
job that also backs up `/home` — see
[Borg Backup](#borg-backup-server-side) below). Memory/uptime state is never
part of the backup — `nas01-backup`'s virtiofs shares can't save/restore that
(see the managed-save troubleshooting entry below) — only the disk, and only
in a consistent, frozen state:

1. `preHook` checks if the VM is running; if so it redirects new writes to a
   throwaway external overlay (`virsh snapshot-create-as --disk-only`), which
   freezes the base qcow2 file with **zero VM downtime**.
2. Borg backs up `/home` and the now-static qcow2 + cloud-init ISO.
3. `postHook` merges the overlay back into the base
   (`virsh blockcommit --active --pivot`) and removes it.

You may see `file changed while we backed it up` logged for the qcow2 file —
this is a borg warning, not a failure (`failOnWarnings = false`, same as
every other host's borg job); the extracted disk has been verified intact
with `qemu-img check`.

Aliases:
```bash
idrive-vm-backup   # trigger an on-demand backup now (also runs nightly)
idrive-vm-list     # list available backup archives (borg list)
idrive-vm-restore  # sudo bash /etc/nas01-backup/vm-restore.sh — restore + start
```

Full disaster-recovery use of `vm-restore.sh` is covered in
[Disaster Recovery](#disaster-recovery--os-ssd-sda-failure) above.

Graphical console access from any Tailscale machine (TigerVNC, KDE's krdc,
Remmina, etc. — no SSH tunnel, no password), e.g. from latitude:
```bash
krdc vnc://nas01.warthog-royal.ts.net:5900
```
nas01 itself stays TUI-only — it no longer runs a VNC client or a GUI remote
desktop session (the old xrdp/openbox/firefox setup was removed 2026-09-02;
it was originally there to reach the IDrive360 web console, but that's a
cloud-hosted page reachable from any browser, not something specific to
nas01's network). This is QEMU's own console VNC (the guest's actual virtual monitor, bound to
nas01's tailscale IP — see `<graphics>` in `nas01-backup-domain.xml`), not an
in-guest VNC server. scott auto-logs into LXDE at boot with no password
(`nopasswdlogin` group), which is what keeps the IDrive360 GUI running
unattended. An earlier design ran a second, in-guest VNC server (x11vnc on
port 5901) as its own desktop session outside logind's seat management,
which caused PolicyKit "No session for pid" failures — removed 2026-08-24.

Manage backups via the [IDrive360 web console](https://www.idrive360.com/enterprise/login).
See [idrive360.md](idrive360.md) → [fkadriver/idrive360](https://github.com/fkadriver/idrive360) for CLI reference (commands run inside the VM).

---

## File Sharing

### NFS

| Export | Clients | Access |
|---|---|---|
| `/pool/data` | 192.168.1.0/24 | rw |
| `/pool/shares/SANS` | LAN (192.168.0.0/16) | ro |
| `/pool/shares/SANS` | Tailscale (100.64.0.0/10) | rw |
| `/pool/shares/photos` | Tailscale | rw |

Verify: `sudo exportfs -v` on nas01, `showmount -e nas01` on a client.

---

## Borg Backup (Server Side)

nas01 is the **backup server**. Clients connect via SSH as `scott` using `id_ed25519_legacy`.
Client-side `BORG_REMOTE_PATH` is `/run/current-system/sw/bin/borg` (set by `modules/borg-backup.nix`).

| Client | Repo path |
|---|---|
| latitude | `/pool/borg/latitude` |
| vm01 | `/pool/borg/vm01` |
| log01 | `/pool/borg/log01` |
| airbook-darwin | `/pool/borg/airbook-darwin` |
| nas01 (itself, local — no SSH) | `/pool/borg/nas01` — `/home` + `nas01-backup` VM disk |

nas01's own job is the same `services.borg-backup` module as the other
hosts, just pointed at a local path instead of `ssh://...`, and with
`preHook`/`postHook` added (see [IDrive360](#idrive360-cloud-backup-qemukvm-vm)
above) to freeze the VM disk consistently before each backup. It exists so
that `/home` and the VM disk survive an OS-SSD failure — see
[Disaster Recovery](#disaster-recovery--os-ssd-sda-failure).

On-server aliases: `borg-repos` (overview), `borg-ls <host>`, `borg-check <host>`, `borg-unlock <host>`.

See [borg-backup.md](borg-backup.md) for client-side setup.

---

## Syncthing

Web UI: `http://127.0.0.1:8384` (tunnel via `ssh -L 8384:localhost:8384 nas01`)

| Folder | Path on nas01 | Shared with |
|---|---|---|
| Documents | `/pool/syncthing/Documents` | latitude, airbook-darwin |
| Downloads | `/pool/syncthing/Downloads` | latitude, airbook-darwin |
| Photos | `/pool/syncthing/Photos` | latitude, airbook-darwin, iphone |

Network: Tailscale-only (declared in `modules/syncthing-declarative.nix`).

---

## Troubleshooting

### eno1 e1000e "Detected Hardware Unit Hang" (HISTORICAL — HP ProDesk only, retired 2026-08)

**This section applies to the retired HP ProDesk box, not the current T330**
(Broadcom BCM5720/`tg3` NICs — confirmed via `ethtool -i eno1` 2026-08-22,
no hang symptoms observed). Kept for reference in case a similar erratum
ever shows up on different NIC hardware in the future.

nas01's onboard NIC (Intel I219, `eno1`) was hanging under normal load
(no builds running) — `dmesg`/journal fills with repeating
`e1000e 0000:00:1f.6 eno1: Detected Hardware Unit Hang` every ~2s, the
interface never recovers on its own, and only a hard/forced reboot
(physical Ctrl-Alt-Del if SSH is already unreachable) clears it.

Timeline:
- **2026-08-03**: disabled EEE (Energy Efficient Ethernet) via
  `ethtool --set-eee eno1 eee off`, suspecting the I219 EEE erratum.
- **2026-08-04**: hang recurred anyway, ~8h into a boot, with EEE
  confirmed disabled the whole time and no link flap/driver reload in
  between — ruled out EEE as the (sole) trigger.
- **2026-08-05**: also disabled TSO/GSO/GRO offload
  (`ethtool -K eno1 tso off gso off gro off`) — the other commonly-cited
  trigger for this same e1000e erratum family.
- **2026-08-06**: confirmed stable for 27+ hours (vs. the previous ~8h
  failure window) — issue considered resolved.

Both fixes lived in `hosts/nas01/default.nix` under
`networking.localCommands`, applied via `network-local-commands.service`
on every boot (they don't survive a driver reload, hence re-applied at
network start rather than set once) — **removed 2026-08-22** now that the
T330 (confirmed `tg3` driver) has replaced the ProDesk. No replacement
mitigation was added speculatively since `tg3` hasn't shown any hang
symptoms; if one ever shows up, start by checking `ethtool -i <iface>` for
the driver in use before assuming this same erratum.

### T330 won't boot from external USB ports (only internal USB header works)

As of 2026-08-21, the only USB port confirmed to work for booting nas01 is
the internal USB header — front/rear external ports haven't been made to
boot anything (unclear if it's a BIOS setting or dirty/dead ports).
Untested leads to check next time this comes up:

- **iDRAC "USB Management Port Mode"**: in the iDRAC Settings Utility,
  confirm it's set to **Automatic** or **Standard OS Use**, not
  iDRAC-Direct-only. Dell's official T330 troubleshooting guide calls this
  out specifically — some PowerEdge towers dedicate one front USB port to
  iDRAC Direct management traffic, in which case the OS/BIOS never sees a
  device plugged into it regardless of port cleanliness.
- **BIOS Integrated Devices**: F2 → System BIOS Settings → Integrated
  Devices → confirm USB Ports is enabled/On for front and rear.
- **Known T330-specific quirk** (Dell community reports): plain USB flash
  drives can be unreliable for boot on this model even on working ports,
  while USB-attached SATA HDD/SSD enclosures boot reliably. Worth testing
  the same stick via a USB-SATA adapter, or GPT/UEFI-formatting the stick
  (e.g. via Rufus), before condemning a port.
- **Isolate hardware vs. BIOS policy without a reboot**: with nas01 already
  booted into NixOS, plug the USB drive into an external port and watch
  `dmesg -w` / `lsusb`. If it enumerates, the port is electrically fine and
  it's a BIOS/iDRAC boot-policy issue (pursue the settings above). If
  nothing shows up, suspect actually dead/dirty contacts — try compressed
  air or an isopropyl-dipped contact cleaner before condemning the port.

Current workaround: a SpinRite USB (prepped via both Ventoy and dd) is
left permanently plugged into the internal USB header for future disk
maintenance boots.

### Recovering the nas01-backup VM from an old OS disk (LVM VG name collision)

While waiting on the HBA330 (ZFS pool not yet connected), the old nas01
box's OS SSD was pulled and connected to the T330 via a USB adapter purely
to recover the `nas01-backup` VM (IDrive360 agent) without needing the
pool/Borg repo.

Problem: the old disk's LVM VG is also named `main_vg` — same as
`disko-config.nix`'s layout on every host — so it collides with the new
install's own root VG.

```bash
# Identify the old disk's VG by UUID, never by name (ambiguous with two
# VGs sharing the same name):
sudo pvs -o pv_name,vg_name,vg_uuid

sudo vgrename <old-vg-uuid> old_nas01_vg
sudo vgchange -ay old_nas01_vg

# Mount read-only and copy the VM's disk + cidata + base cloud image —
# all three needed, the qcow2 is copy-on-write against the base image:
sudo mount -o ro /dev/old_nas01_vg/root /mnt/old
sudo cp /mnt/old/var/lib/libvirt/images/{nas01-backup.qcow2,nas01-backup-cidata.iso,ubuntu-24.04-cloud.img} \
  /var/lib/libvirt/images/

sudo virsh define /etc/nas01-backup/domain.xml
sudo virsh start nas01-backup
```

### nas01-backup VM has no network after recovery/redefine

VM boots fine (VNC shows a login screen) but never gets a DHCP lease — no
Tailscale, Wazuh agent unreachable. Cause: `hosts/nas01/nas01-backup-domain.xml`
had no pinned `<mac address>`, so `virsh define` assigns a random MAC each
time. The guest's cloud-init-baked netplan
(`/etc/netplan/50-cloud-init.yaml`) matches on a specific MAC
(`52:54:00:b8:1a:d8`) — mismatch means the NIC comes up `state DOWN` with no
lease, even though the VM otherwise boots normally.

Diagnose with the QEMU guest agent even with zero network:
```bash
virsh domifaddr --source agent nas01-backup
virsh qemu-agent-command nas01-backup '{"execute":"guest-exec", ...}'
```

Fixed by pinning `<mac address='52:54:00:b8:1a:d8'/>` in `domain.xml`
(commit `0370822`) — already fixed going forward, but worth knowing if
`domain.xml` is ever hand-edited or the VM redefined from scratch.

### Borg timers won't stay masked across reboots (read-only `/etc`)

While the ZFS pool is disconnected (waiting on the HBA330), the three borg
timers (`borgbackup-job-system.timer`, `borg-status.timer`,
`borg-restore-test.timer`) need to stay masked so they don't fire against a
nonexistent `/pool/borg/nas01`. A normal persistent `systemctl mask` fails
with "Read-only file system" — this host has NixOS's read-only-`/etc`
protection enabled. Only a runtime mask works, and it does **not survive a
reboot**:

```bash
sudo systemctl mask --runtime borgbackup-job-system.timer borg-status.timer borg-restore-test.timer
```

Re-check `systemctl is-active borgbackup-job-system.timer` after every
reboot until the pool is actually imported, and re-run the mask if it's
back to active. Unmask once `/pool/borg` is real:
```bash
sudo systemctl unmask --runtime borgbackup-job-system.timer borg-status.timer borg-restore-test.timer
```

### ZFS pool didn't import

```bash
zpool import                 # list importable pools
sudo zpool import -f pool    # force if never cleanly exported
zpool status
```

### NFS mounts failing on clients

```bash
sudo exportfs -v             # on nas01
showmount -e nas01           # on client
```

### Salvaging old borg repos from the WD drive (RESOLVED 2026-08-22 — drive is healthy)

The WD 18TB drive dropped off the SATA bus in 2026-07 and was written off as
failing at the time. It stress-tested clean under SpinRite on the T330 and
is now mounted normally on both `/mnt/wd18t_1` and `/mnt/wd18t_3` with data
intact — this section is now historical/precautionary rather than an active
concern. If it ever drops offline again, copy the old repo history onto the
pool before further troubleshooting:

```bash
sudo rsync -a /mnt/wd18t_3/borg/repos/ /pool/borg/
sudo chown -R scott /pool/borg
```

If the drive is ever lost for good, clients simply init fresh repos on their
first backup (history lost; the IDrive360 cloud copy of `/mnt` may also hold
the old repos).

### IDrive360 VM

```bash
idrive-status    # virsh domstate nas01-backup — VM running?
idrive-ssh       # ssh into the VM
```

See `docs/idrive360.md` → [fkadriver/idrive360](https://github.com/fkadriver/idrive360)
for full IDrive360 operations (VM-based since the Docker containers were
removed — see commit b20740e).

### `virsh start nas01-backup` fails with "unexpected fatal signal 13"

```
error: internal error: Child process (... libvirt_iohelper .../nas01-backup.save 0) unexpected fatal signal 13
error: Unable to restore from managed state ... Maybe the file is corrupted?
```

Cause: `nas01-backup` has virtiofs shares (`/pool`, `/mnt`), which don't
support save/restore — the virtiofsd backend state can't be serialized. If
libvirt ever managed-saves this VM (e.g. `libvirt-guests.service` suspending
it on a host shutdown/reboot), the restore-on-boot fails with a SIGPIPE and
leaves a stuck, unrestorable save image; every subsequent `virsh start`
repeats the same failure until it's cleared.

Fix (one-time, to recover a stuck VM):
```bash
sudo virsh managedsave-remove nas01-backup
sudo virsh start nas01-backup
```

This is already prevented going forward: `virtualisation.libvirtd.onShutdown`
is set to `"shutdown"` (ACPI shutdown instead of suspend), so
`nas01-backup` always cold-boots and this can't recur from a normal host
reboot.

### New `services.wazuh-agent` localfile/command not showing up on the manager

`fixPermsScript` (in `modules/wazuh-agent.nix`) symlinks any script it finds
at `/usr/local/bin/wazuh-*` into `/var/ossec/scripts/` (the only place
visible inside the FHS-sandboxed `wazuh-logcollector`), but it only runs via
`ExecStartPre` on `wazuh-agent.service` — i.e. once, at that service's last
start. If you enable a new script-backed check (e.g. `services.borg-backup`,
which ships `/usr/local/bin/wazuh-borg-status`) on a host where
`wazuh-agent.service` was already running, the symlink won't exist until you
restart it:

```bash
sudo systemctl restart wazuh-agent.service
sudo ls -la /var/ossec/scripts/   # confirm the new symlink resolves
```
