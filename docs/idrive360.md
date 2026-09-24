# IDrive360

Everything learned about running and troubleshooting IDrive360 — device
identity gotchas, CLI usage, troubleshooting guides, the support ticket
history, network ports, etc. — lives in its own private repo:

**[github.com/fkadriver/idrive360](https://github.com/fkadriver/idrive360)**

That repo is knowledge/ops content only. Provisioning stays here.

**Active agent: `sands-bak01`** (dedicated hardware, HP ProDesk 600 G4 DM —
migrated off the VM below on 2026-09-23/24, see the idrive360 repo's
`MIGRATION.md` for the full story):

- [`hosts/sands-bak01/setup.sh`](../hosts/sands-bak01/setup.sh) — provisioning
  script for a fresh Ubuntu Server 24.04 minimal install. Not a flake target
  (IDrive360's Electron client needs a normal Ubuntu desktop stack, not
  NixOS) — run by hand after the base OS install, the only declarative
  record of this host's config.

**Retired: the `nas01-backup` VM** (kept intact for potential rollback, not
removed — shut down, autostart disabled). Still referenced directly by
[`hosts/nas01/default.nix`](../hosts/nas01/default.nix):

- [`hosts/nas01/nas01-backup-setup.sh`](../hosts/nas01/nas01-backup-setup.sh) — cloud-init VM setup script
- [`hosts/nas01/nas01-backup-domain.xml`](../hosts/nas01/nas01-backup-domain.xml) — libvirt VM definition
- [`hosts/nas01/nas01-backup-vm-restore.sh`](../hosts/nas01/nas01-backup-vm-restore.sh) — VM disk restore script

See also [`nas01.md`](nas01.md) for the host `nas01` more broadly (ZFS pool,
Borg backups, Syncthing, etc. — nas01-backup was just one VM it hosted).
