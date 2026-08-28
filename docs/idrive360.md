# IDrive360 on nas01

Everything learned about running and troubleshooting IDrive360 (the
`nas01-backup` VM's backup agent) — device identity gotchas, CLI usage,
troubleshooting guides, the support ticket history, network ports, etc. —
now lives in its own private repo:

**[github.com/fkadriver/idrive360](https://github.com/fkadriver/idrive360)**

That repo is knowledge/ops content only. The VM's actual provisioning stays
here, since it's referenced directly by
[`hosts/nas01/default.nix`](../hosts/nas01/default.nix):

- [`hosts/nas01/nas01-backup-setup.sh`](../hosts/nas01/nas01-backup-setup.sh) — cloud-init VM setup script
- [`hosts/nas01/nas01-backup-domain.xml`](../hosts/nas01/nas01-backup-domain.xml) — libvirt VM definition
- [`hosts/nas01/nas01-backup-vm-restore.sh`](../hosts/nas01/nas01-backup-vm-restore.sh) — VM disk restore script

See also [`nas01.md`](nas01.md) for the host `nas01` more broadly (ZFS pool,
Borg backups, Syncthing, etc. — nas01-backup is just one VM it hosts).
