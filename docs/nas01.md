# nas01 — NAS Server Reference

nas01 is a NixOS host (converted from Ubuntu in July 2026 after a permissions accident broke sudo/root). The entire system — ZFS, Samba, NFS, Syncthing, Borg server, Tailscale, IDrive360 — is declared in [hosts/nas01/default.nix](../hosts/nas01/default.nix).

The Ubuntu-era `apply.sh` deployment is archived at `archive/hosts/nas01-ubuntu/`.

## Hardware

- **Role**: NAS — file serving, Borg backup server, Syncthing hub, IDrive360 cloud backup
- **Tailscale hostname**: `nas01.warthog-royal.ts.net`

### Drives

| Drive | Mount | Purpose |
|---|---|---|
| Micron 256GB SSD (serial UGXVK01J7C9TJA) | `/` (LVM/ext4 via disko) | OS |
| 3x 4TB HGST (RAIDZ1) | `/pool` | ZFS pool — NAS data + borg repos (lz4, ashift=12) |
| WD 18TB | `/mnt/wd18t_1`, `/mnt/wd18t_3` | **FAILING (2026-07)** — mounts kept `nofail` for salvage only |

The ZFS pool and WD drive are **not** managed by disko — they carry data across OS reinstalls.

---

## Fresh Installation

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

### 3. Import the ZFS pool and create the borg dataset (one-time)

```bash
sudo zpool import -f pool   # -f: pool wasn't cleanly exported from old OS
sudo zfs create -o compression=lz4 pool/borg
sudo chown scott:users /pool/borg && sudo chmod 750 /pool/borg
```

`boot.zfs.extraPools` auto-imports the pool on subsequent boots. Clients
auto-init their repos at `/pool/borg/<hostname>` on their first backup run.

### 4. Restore Syncthing identity (keeps device ID, no re-pairing)

Copy `cert.pem`, `key.pem` from the pre-rebuild backup into
`/home/scott/.config/syncthing/` before syncthing first starts.

### 5. Samba password (not declarative)

```bash
sudo smbpasswd -a scott
```

### 6. Seed IDrive360 (see below)

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
| IDrive360 | `virtualisation.oci-containers.containers.idrive360` | see below |

---

## IDrive360 (cloud backup, containerized)

IDrive360's installer self-updates and downloads its backup engine at runtime,
which is incompatible with Nix packaging (prior attempt: `archive/pkgs/idrive-e360/`).
It runs in an `ubuntu:24.04` Docker container instead:

- **State**: `/var/lib/idrive360/opt` → `/opt/IDrive360` in-container (persistent volume; holds device registration + engine)
- **Seed**: `/var/lib/idrive360/seed` — installer `.deb` (token in filename) + rescued `idrive360cron` binary
- **Data mounts**: `/pool` and `/mnt` read-only (backup set covers /pool, /mnt, /opt)
- **Entrypoint**: [hosts/nas01/idrive360-entrypoint.sh](../hosts/nas01/idrive360-entrypoint.sh) — restores deps/cron binary on container recreation, falls back to full `dpkg -i` bootstrap, then runs `/etc/idrive360cron --cron`

Seeding after a rebuild (from the latitude backup):
```bash
rsync -a ~/nas01-backup/opt-IDrive360/ nas01:/var/lib/idrive360/opt/
scp ~/nas01-backup/home/IDrive360_*.deb ~/nas01-backup/etc/idrive360cron.bin \
    nas01:/var/lib/idrive360/seed/
```

Manage via the [IDrive360 web console](https://www.idrive360.com/enterprise/login).
Logs: `journalctl -u docker-idrive360`.

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

### IDrive360 container

```bash
docker ps                            # container running?
journalctl -u docker-idrive360 -n 50
docker exec -it idrive360 bash       # poke inside
```
