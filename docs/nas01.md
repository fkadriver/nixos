# nas01 — NAS Server Reference

nas01 is an Ubuntu-based NAS (not NixOS). Configuration is managed via this repo and deployed with `apply.sh`. Nix is used only for userspace packages — the OS, kernel modules, and core services are managed by Ubuntu/apt/systemd.

## Hardware

- **OS**: Ubuntu 25.10
- **Role**: NAS — file serving, Borg backup server, Syncthing hub
- **Tailscale hostname**: `nas01.warthog-royal.ts.net`

### Drives

| Drive | Mount | Purpose |
|---|---|---|
| 3x 4TB HGST (RAIDZ1) | `/pool` | ZFS pool — NAS data |
| WD 18TB | `/mnt/wd18t_3` | Borg backup repos, large storage |

---

## Fresh Deployment

### 1. Install Ubuntu prerequisites

```bash
sudo apt install curl git
sudo apt install nfs-kernel-server zfsutils-linux
sudo apt install docker.io
sudo usermod -aG docker scott
```

> `zfsutils-linux` and `nfs-kernel-server` must be apt-managed — they require kernel module integration via DKMS that Nix cannot provide.

### 2. Clone repo and run apply.sh

```bash
git clone git@github.com:fkadriver/nixos ~/git/nixos
cd ~/git/nixos
sudo ./hosts/nas01/apply.sh
```

`apply.sh` handles:
- Installing Nix (if not present)
- Building and installing the Nix package profile at `/nix/var/nix/profiles/nas01`
- Adding the Nix profile to system-wide `PATH` via `/etc/profile.d/nas01-nix.sh`
- Applying home-manager config (shell aliases, starship, bash config)
- Deploying SSH keys from `secrets.yaml` via sops
- Installing `smb.conf`, NFS exports, and systemd service files
- Reloading systemd

### 3. Enable services

```bash
sudo systemctl enable --now smbd nmbd
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -ra
sudo systemctl enable --now tailscaled
sudo tailscale up                       # one-time Tailscale auth
sudo systemctl enable --now syncthing
bash ~/git/nixos/hosts/nas01/config/syncthing-setup.sh
```

### 4. Set up ZFS pool (first time or new drives)

```bash
# Identify drives first
ls -la /dev/disk/by-id/ | grep -v part
lsblk -o NAME,SIZE,MODEL,SERIAL

# Fill in DISK1/2/3 in zfs-setup.sh, then:
sudo bash ~/git/nixos/hosts/nas01/config/zfs-setup.sh
sudo chown -R scott:scott /pool/data
```

See [zfs-cheatsheet.md](zfs-cheatsheet.md) for ZFS commands reference.

### 5. Set up Borg server

```bash
sudo bash ~/git/nixos/hosts/nas01/config/borg-server-setup.sh
```

Creates `/mnt/wd18t_3/borg/{latitude,vm01,airbook-darwin}` with correct ownership.

### 6. Set up sops age key (one-time, for SSH key deployment)

```bash
sudo age-keygen -o /var/lib/sops-nix/key.txt
# Copy the public key output
# Add it to .sops.yaml in the repo, then re-encrypt:
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops updatekeys secrets/secrets.yaml
```

---

## Ongoing Maintenance

### Apply config changes

```bash
nix-apply   # alias: cd ~/git/nixos && git pull && sudo ./hosts/nas01/apply.sh
```

### Update packages only

```bash
cd ~/git/nixos && nix flake update && sudo ./hosts/nas01/apply.sh
```

---

## Nix Package Profile

Managed in [hosts/nas01/packages.nix](../hosts/nas01/packages.nix).
Installed to: `/nix/var/nix/profiles/nas01`

| Package | Purpose |
|---|---|
| `borgbackup` | Borg backup server (SSH-based) |
| `samba` | SMB/CIFS file sharing |
| `nfs-utils` | NFS userspace tools |
| `rsync` | File transfers / migration |
| `smartmontools` | Drive health (`smartctl`) |
| `hdparm` | Drive identification |
| `hddtemp` | Hard drive temperature |
| `lm_sensors` | CPU/board temperature (`sensors`) |
| `btop` | TUI system monitor |
| `ncdu` | Disk usage analyzer |
| `htop` | Process monitor |
| `lsof` | Open file/socket inspection |
| `docker` | Container runtime (CLI) |
| `tailscale` | VPN |
| `syncthing` | File sync |
| `sops` / `age` | Secrets decryption |
| `home-manager` | Shell config management |
| `vim` | Text editor |
| `tree` | Directory viewer |

---

## Storage Layout

```
/pool/                      ZFS RAIDZ1 (3x 4TB HGST)
  data/                     Main NAS data — SMB share [data], NFS export

/mnt/wd18t_3/               WD 18TB drive
  borg/                     Borg backup repos
    latitude/
    vm01/
    airbook-darwin/
```

---

## Services

All services run binaries from `/nix/var/nix/profiles/nas01/bin/` via custom systemd unit files installed to `/etc/systemd/system/`.

| Service | Unit file | Managed by |
|---|---|---|
| Samba (SMB) | `smbd.service`, `nmbd.service` | systemd (Nix binary) |
| NFS | `nfs-kernel-server` | apt / systemd |
| Tailscale | `tailscaled.service` | systemd (Nix binary) |
| Syncthing | `syncthing.service` | systemd (Nix binary, runs as scott) |
| Docker | `docker` | apt / systemd |
| ZFS | built into kernel | apt (DKMS) |

### Service management

```bash
sudo systemctl status smbd nmbd nfs-kernel-server tailscaled syncthing docker

# Restart a service
sudo systemctl restart smbd

# View logs
sudo journalctl -u smbd -n 50
sudo journalctl -u syncthing -n 50
```

---

## File Sharing

### SMB (Samba)

Config: [hosts/nas01/config/smb.conf](../hosts/nas01/config/smb.conf)
Restricted to `192.168.1.0/24`. Authentication required (`valid users = scott`).

| Share | Path | Access |
|---|---|---|
| `[data]` | `/pool/data` | read/write, scott only |
| `[borg]` | `/mnt/wd18t_3/borg` | read-only browse |

Samba password (separate from Linux password):
```bash
sudo smbpasswd -a scott
```

### NFS

Config: [hosts/nas01/config/exports](../hosts/nas01/config/exports)

```
/pool/data    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Reload after changes:
```bash
sudo exportfs -ra
sudo exportfs -v    # verify active exports
```

---

## Borg Backup (Server Side)

nas01 is the **backup server**. Clients connect via SSH as `scott` using `id_ed25519_legacy`.

| Client | Repo path |
|---|---|
| latitude | `/mnt/wd18t_3/borg/latitude` |
| vm01 | `/mnt/wd18t_3/borg/vm01` |
| airbook-darwin | `/mnt/wd18t_3/borg/airbook-darwin` |

### Useful aliases (run on nas01)

```bash
borg-repos      # List all repos with last backup timestamp
```

### Manually inspect a repo (on nas01)

```bash
sudo env BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase" \
    borg list /mnt/wd18t_3/borg/latitude
```

See [borg-backup.md](borg-backup.md) for client-side setup and full alias reference.

---

## Syncthing

Web UI: `http://nas01.warthog-royal.ts.net:8384` (Tailscale only)

Syncs these folders with latitude and airbook-darwin:

| Folder | Path on nas01 |
|---|---|
| Documents | `~/syncthing/Documents` |
| Downloads | `~/syncthing/Downloads` |
| Photos | `~/syncthing/Photos` |

Network: Tailscale-only (global announce, relay, and NAT traversal disabled).

Reconfigure from scratch:
```bash
bash ~/git/nixos/hosts/nas01/config/syncthing-setup.sh
```

---

## Secrets (SSH Keys)

SSH keys are deployed from `secrets/secrets.yaml` by `apply.sh` via sops+age.

| Key | Purpose |
|---|---|
| `id_ed25519` | Primary SSH key |
| `id_ed25519_github` | GitHub access |
| `id_ed25519_legacy` | Borg client auth (all backup clients use this) |
| `opnsense_admin_ed25519` | OPNsense router admin |

Age key location: `/var/lib/sops-nix/key.txt`

---

## Troubleshooting

### Nix profile not in PATH after sudo

```bash
export PATH="/nix/var/nix/profiles/nas01/bin:$PATH"
# Or source the profile:
source /etc/profile.d/nas01-nix.sh
```

### Samba not accessible

```bash
sudo systemctl status smbd nmbd
sudo smbstatus                          # active connections
sudo testparm                           # validate smb.conf
```

### NFS mounts failing on clients

```bash
sudo exportfs -ra                       # reload exports
sudo exportfs -v                        # check active exports
sudo systemctl status nfs-kernel-server
# On client: showmount -e nas01
```

### ZFS pool degraded

```bash
zpool status                            # identify failed/faulted drive
# See zfs-cheatsheet.md for drive replacement steps
```

### iDrive e360 (cloud backup)

iDrive cannot be packaged via Nix — install the `.deb` directly from the iDrive website (Endpoint Backup → Add Devices → Linux). See `archive/modules/idrive-e360.nix` for prior packaging attempt.
