# ZFS Quick Reference

## Pool Status

```bash
zpool status                        # Pool health and disk layout
zpool status -v                     # Verbose: show errors per device
zpool list                          # Pool size, usage, health
zfs list                            # All datasets: size, used, mountpoint
zfs list -t all                     # Datasets + snapshots
```

## Pool Operations

```bash
# Import/export (e.g. moving pool to new machine)
zpool export pool
zpool import pool

# Scrub (verify data integrity, run monthly)
zpool scrub pool
zpool scrub -s pool                 # Stop a running scrub

# Clear error counters after fixing a drive
zpool clear pool
```

## Datasets

```bash
# Create
zfs create pool/data
zfs create -o compression=lz4 pool/data

# Destroy (irreversible)
zfs destroy pool/data               # Must be empty
zfs destroy -r pool/data            # Recursive: dataset + children + snapshots

# Properties
zfs get all pool/data               # Show all properties
zfs get compression,used pool/data  # Specific properties
zfs set compression=lz4 pool/data
zfs set atime=off pool/data
zfs set quota=500G pool/data        # Limit dataset size

# Rename / move
zfs rename pool/old pool/new
```

## Snapshots

```bash
# Create
zfs snapshot pool/data@2026-03-25
zfs snapshot -r pool/data@2026-03-25  # Recursive (all children)

# List
zfs list -t snapshot
zfs list -t snapshot pool/data

# Destroy
zfs destroy pool/data@2026-03-25

# Rollback (reverts dataset to snapshot state)
zfs rollback pool/data@2026-03-25
zfs rollback -r pool/data@2026-03-25  # Also destroys newer snapshots

# Diff (what changed between snapshot and now)
zfs diff pool/data@2026-03-25 pool/data
```

## Send / Receive (Backup & Replication)

```bash
# Full send to file
zfs send pool/data@snap1 > /mnt/backup/data.zfs

# Incremental send (only changes between two snapshots)
zfs send -i pool/data@snap1 pool/data@snap2 | ssh nas01 zfs receive backup/data

# Send with compression over SSH
zfs send pool/data@snap1 | ssh nas01 zfs receive backup/data
```

## Drive Management (RAIDZ)

```bash
# Replace a failed drive
zpool offline pool /dev/disk/by-id/old-disk-id
zpool replace pool /dev/disk/by-id/old-disk-id /dev/disk/by-id/new-disk-id
zpool online pool /dev/disk/by-id/new-disk-id

# Watch resilver progress
zpool status pool

# Add a spare
zpool add pool spare /dev/disk/by-id/spare-disk-id
```

## Disk Usage

```bash
zfs list -o name,used,avail,refer,mountpoint
zfs list -r pool                    # Recursive breakdown
du -sh /pool/data/*                 # Standard disk usage within dataset
```

## nas01 Pool Layout

| Dataset     | Mount       | Notes                              |
|-------------|-------------|------------------------------------|
| `pool`      | `/pool`     | RAIDZ1 across 3x 4TB HGST drives  |
| `pool/data` | `/pool/data`| NFS exports                         |

Borg repos: `/mnt/wd18t_3/borg/repos/` (WD 18TB drive, not on ZFS pool)

## Useful One-liners

```bash
# Check compression ratio
zfs get compressratio pool/data

# How much space each snapshot is consuming
zfs list -t snapshot -o name,used,refer

# Pool I/O statistics (live)
zpool iostat 2                      # Refresh every 2 seconds
zpool iostat -v 2                   # Per-disk breakdown

# Identify which dataset is using space
zfs list -r -o name,used,usedbychildren,usedbysnapshots,usedbyrefreservation pool
```
