# nas01 — NAS Server Reference

nas01 is a NixOS host (converted from Ubuntu in July 2026 after a permissions accident broke sudo/root). The entire system — ZFS, Samba, NFS, Syncthing, Borg server, Tailscale, IDrive360 — is declared in [hosts/nas01/default.nix](../hosts/nas01/default.nix).

The Ubuntu-era `apply.sh` deployment is archived at `archive/hosts/nas01-ubuntu/`.

## Hardware

- **Role**: NAS — file serving, Borg backup server, Syncthing hub, IDrive360 cloud backup
- **Model**: HP ProDesk 600 G4 DM (TAA) — Desktop Mini, serial MXL9231YDY, BIOS Q22 Ver. 02.06.03
- **CPU**: Intel Core i5-8500T @ 2.10GHz (6 cores/6 threads, no HT, turbo to 3.5GHz)
- **Memory**: 8GB DDR4 SODIMM @ 2667 MT/s (1 of 2 slots populated — expandable)
- **Tailscale hostname**: `nas01.warthog-royal.ts.net`

### Drives

| Drive | Mount | Purpose |
|---|---|---|
| Micron MTFDDAK256TBN 256GB SATA SSD (serial UGXVK01J7C9TJA) | `/` (LVM/ext4 via disko) | OS |
| 3x HGST HDS724040ALE640 4TB 7200rpm (RAIDZ1) | `/pool` | ZFS pool — NAS data + borg repos (lz4, ashift=12) |
| WD WD180EDGZ-11BLDS0 18TB 7200rpm | `/mnt/wd18t_1`, `/mnt/wd18t_3` | **FAILING (2026-07)** — mounts kept `nofail` for salvage only |

The ZFS pool and WD drive are **not** managed by disko — they carry data across OS reinstalls.

---

## Disaster Recovery — OS SSD (sda) Failure

nas01's OS disk (the Micron SSD) is a single, non-redundant drive. Everything
on it is either declarative (rebuildable from this flake) or backed up to
`/pool` (the redundant ZFS raidz1 array, which lives on three *other* physical
disks and survives an OS-SSD failure untouched). The only things that are
**not** reproducible from git are `/home` and the `nas01-backup` VM's disk —
both are backed up nightly to `/pool/borg/nas01` (see
[Borg Backup](#borg-backup-server-side) below) specifically so this runbook
can restore them.

These same steps also apply to an intentional fresh install (e.g. a new OS
SSD), not just a failure.

### 1. Partition OS disk and install (from NixOS installer USB)

```bash
# Identify the OS SSD by-id (Micron, serial UGXVK01J7C9TJA):
ls -la /dev/disk/by-id/ | grep -i micron

# Partition ONLY the OS SSD (ZFS/WD drives untouched):
sudo nix run github:nix-community/disko -- --mode disko \
  --flake github:fkadriver/nixos#nas01 \
  --arg device '"/dev/disk/by-id/ata-Micron_..._UGXVK01J7C9TJA"'

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

### 6. Samba password (not declarative)

```bash
sudo smbpasswd -a scott
```

### 7. Verify

```bash
zpool status                        # pool healthy
sudo systemctl status samba-smbd    # file sharing up
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
  data/                     Main NAS data — SMB share [data], NFS export
  shares/                   SANS + photos NFS exports
  syncthing/                Syncthing folders (Documents, Downloads, Photos)
  borg/                     Borg backup repos: <hostname> per client

/mnt/wd18t_3/               WD 18TB drive — failing, salvage only
```

---

## Services

All declared in [hosts/nas01/default.nix](../hosts/nas01/default.nix):

| Service | NixOS option | Notes |
|---|---|---|
| Samba | `services.samba` | shares `[data]` rw, `[borg]` ro; LAN + Tailscale |
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
- **Desktop**: LXDE + x11vnc on port 5901 (bound to VM NAT IP, not nas01 localhost)
- **VM definition**: `hosts/nas01/nas01-backup-domain.xml` deployed to `/etc/nas01-backup/domain.xml`
- **Setup script**: `hosts/nas01/nas01-backup-setup.sh` deployed to `/etc/nas01-backup/setup.sh`

One-time setup (already done — the VM is registered and running):
```bash
sudo bash /etc/nas01-backup/setup.sh
```

Useful aliases (available in scott's shell on nas01):
```bash
idrive-status    # virsh domstate nas01-backup
idrive-start     # sudo virsh start nas01-backup
idrive-stop      # sudo virsh shutdown nas01-backup
idrive-ssh       # ssh directly into the VM
idrive-console   # serial console (Ctrl+] to exit)
```

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

Known caveat: these files are rewritten in place on each update, not
appended to. Wazuh's log collector detects truncation (new content shorter
than what it last read) and re-reads from the start, but if a rewrite
happens to produce content the same length or longer, it can miss or garble
that update — a generic tail-vs-rewrite limitation, not an IDrive360 bug.
Acceptable here since these are point-in-time status snapshots, not an
audit trail.

Baked into `nas01-backup-setup.sh`'s cloud-init
(`idrive360-wazuh-localfiles.py`, idempotent) so a fresh VM build gets this
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

VNC access from a remote machine (e.g. Remmina on Tailscale):
```bash
# Open SSH tunnel on the remote machine (keep open while using VNC):
ssh -L 5901:192.168.122.54:5901 -N scott@nas01.warthog-royal.ts.net

# Connect Remmina to localhost:5901, password: changeme
# (disable Remmina's built-in SSH tunnel — Tailscale SSH is incompatible with libssh)
```

Manage backups via the [IDrive360 web console](https://www.idrive360.com/enterprise/login).
See [idrive360.md](idrive360.md) for CLI reference (commands run inside the VM).

---

## File Sharing

### SMB (Samba)

Restricted to `192.168.1.0/24` + Tailscale. Authentication required (`valid users = scott`).

| Share | Path | Access |
|---|---|---|
| `[data]` | `/pool/data` | read/write, scott only |
| `[borg]` | `/pool/borg` | read-only browse |

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

### ZFS pool didn't import

```bash
zpool import                 # list importable pools
sudo zpool import -f pool    # force if never cleanly exported
zpool status
```

### Samba not accessible

```bash
sudo systemctl status samba-smbd
sudo smbstatus
# Password set? sudo smbpasswd -a scott
```

### NFS mounts failing on clients

```bash
sudo exportfs -v             # on nas01
showmount -e nas01           # on client
```

### Salvaging old borg repos from the failing WD drive

If `/mnt/wd18t_3` mounts after the rebuild (nofail — it dropped off the old
Ubuntu install), copy the old repo history onto the pool before the drive dies:

```bash
sudo rsync -a /mnt/wd18t_3/borg/repos/ /pool/borg/
sudo chown -R scott /pool/borg
```

If the drive is gone, clients simply init fresh repos on their first backup
(history lost; the IDrive360 cloud copy of `/mnt` may also hold the old repos).

### IDrive360 VM

```bash
idrive-status    # virsh domstate nas01-backup — VM running?
idrive-ssh       # ssh into the VM
```

See `docs/idrive360.md` for full IDrive360 operations (VM-based since the
Docker containers were removed — see commit b20740e).

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
