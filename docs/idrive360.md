# IDrive360 on nas01 — Operations Reference

IDrive360 runs inside the `nas01-backup` QEMU/KVM VM (Ubuntu 24.04).
All CLI access goes through SSH into the VM. The web console is at
[idrive360.com/enterprise/login](https://www.idrive.com/enterprise/login).

**Device user hash**: `he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets`
(appears in many CLI commands as the device/account identifier; this changes if
the device is ever re-registered — confirm the current value with
`ls /opt/IDrive360/idriveIt/user_profile/scott/` before trusting the examples below)

---

## VM access

```bash
# SSH into the VM (from nas01)
idrive-ssh          # alias: ssh scott@$(virsh domifaddr nas01-backup | awk '/ipv4/{print $4}' | cut -d/ -f1)

# Serial console (Ctrl+] to exit)
idrive-console

# VM status / power
idrive-status       # virsh domstate nas01-backup --reason
idrive-start        # sudo virsh start nas01-backup
idrive-stop         # sudo virsh shutdown nas01-backup
```

Graphical console from any Tailscale machine (TigerVNC, Remmina, etc. — no
tunnel needed, no password):
```bash
idrive-console-vnc   # alias: vncviewer nas01.warthog-royal.ts.net:5900
```
This is QEMU's own console VNC (the guest's actual virtual monitor), bound to
nas01's tailscale IP — reachability is gated by tailnet membership, same as
everything else in the fleet. scott auto-logs into LXDE at boot (no password:
scott is in the `nopasswdlogin` group), which is what keeps the IDrive360 GUI
running unattended. There is deliberately no in-guest VNC server (x11vnc/Xvfb)
anymore — an earlier design ran one on port 5901 as a second, separate
desktop session outside logind's seat management, which caused a PolicyKit
"No session for pid" failure mode. See git history around 2026-08-24 if this
ever needs re-deriving.

---

## IDrive360 service management (inside the VM)

```bash
# Is the agent running?
systemctl status idrive360cron

# Tail live logs
journalctl -u idrive360cron -f
journalctl -u idrive360cron -n 100

# Start / stop / restart
sudo systemctl restart idrive360cron
sudo systemctl stop   idrive360cron
sudo systemctl start  idrive360cron

# Drop into a shell
ssh scott@<VM-IP>       # or: idrive-ssh from nas01
sudo -i                 # root shell if needed
```

### Desktop shortcut (inside the VM's LXDE session)

`~/Desktop/Restart-IDrive360-Service.desktop` runs
`/usr/local/bin/idrive360-restart-service.sh` in an `lxterminal` window —
`sudo systemctl restart idrive360cron` (scott has passwordless sudo in this
VM) and prints the result. Both files need to survive a VM disk restore for
this to keep working — they do, since the whole `nas01-backup` qcow2 disk is
backed up nightly (see [nas01.md](nas01.md#vm-disk-backup-and-restore)), not
just `/home`.

The IDrive360 GUI client already autostarts on login — the vendor's `.deb`
installer drops `~/.config/autostart/idrive360client.desktop`
(`idrive360-client --hidden`), which LXDE runs automatically every time
scott's console session (auto-)starts. No changes needed there; confirmed
running via `ps aux | grep idrive360-client`.

---

## How to run IDrive360 CLI commands

The main binary is `/opt/IDrive360/idrive360`. All backup/status operations run **as user `scott`** inside the VM.

SSH into the VM first, then:

```bash
/opt/IDrive360/idrive360 <flag> [args]

# Check active schedule
cat /etc/idrive360crontab.json
```

---

## Known CLI commands

### Run a scheduled backup

```bash
/opt/IDrive360/idrive360 --backup SCHEDULED \
  he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets
```

### Stop / terminate a backup job

```bash
/opt/IDrive360/idrive360 --terminate-job backup - 2
```

`backup` is the job type; `2` is the backup set index (default_backupset = 2).
Run this when the web console shows a job as "running" but nothing is uploading.

### Check for / install updates

```bash
/opt/IDrive360/idrive360 --install update
```

---

## Stop all backup jobs

### Option 1 — terminate-job (clean stop, tells the server)

```bash
/opt/IDrive360/idrive360 --terminate-job backup - 2
```

### Option 2 — kill the backup process directly

```bash
# Find the backup subprocess
ps aux | grep idrive360

# Kill it (replace <PID>)
kill <PID>
```

### Option 3 — restart the service (blunt but reliable)

```bash
sudo systemctl restart idrive360cron
journalctl -u idrive360cron -f    # watch it come back up
```

---

## Troubleshooting: job shows "running" in web console but nothing is uploading

This is a known IDrive360 state-sync issue — the server thinks a job is active
but the agent process has exited or stalled.

**Confirm the job is a phantom:**

```bash
ps aux | grep idrive360
```

If you only see the cron daemon and background services but no `--backup` subprocess, nothing is running.

**Fix sequence:**

1. Run `--terminate-job` to clear the server-side state:
   ```bash
   /opt/IDrive360/idrive360 --terminate-job backup - 2
   ```

2. If that doesn't clear it in the web console after ~2 minutes, restart the service:
   ```bash
   sudo systemctl restart idrive360cron
   ```

3. If the console still shows it running, use the web console's **Stop Backup** button.

---

## Troubleshooting: backup stuck since a specific date (stale lock files)

**Root cause**: A backup crash leaves behind stale lock files. The engine sees
`ENGINE_LOCKE_FILE` + a non-empty `LOGPID` pointing to a `Running_Scheduled` log
and refuses to start any new job.

**Diagnose:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets"

ls -la "$PROFILE/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE"
cat "$PROFILE/Backup/DefaultBackupSet/LOGPID"
ls "$PROFILE/CONFIGURATION_FILE.corrupt-"* 2>/dev/null
cat "$PROFILE/.userInfo/lastBackupStatus.txt"
```

**Fix — clear stale locks and restart:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets"
LOGS="$PROFILE/Backup/DefaultBackupSet/LOGS"

rm -f "$PROFILE/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE"
echo '' > "$PROFILE/Backup/pid.txt"
echo '' > "$PROFILE/Backup/DefaultBackupSet/LOGPID"

# Rename any Running_Scheduled log to Failure
for f in "$LOGS"/*_Running_Scheduled; do
  [ -f "$f" ] && mv "$f" "${f/_Running_/_Failure_}" && echo "Renamed: $f"
done

sudo systemctl restart idrive360cron
```

---

## Troubleshooting: Wazuh/console shows "unexpected error" / Failure, but data is actually backing up

**Known vendor bug**, confirmed still present in the latest available
`idrive360-client` (1.3.0 → 1.3.0, `idrive360 --install update` found nothing
newer as of 2026-08-10).

**Root cause**: the backup engine's finalization step tries to open a bare
`.../DefaultBackupSet/pid.txt`, but the client only ever writes rotated copies
(`pid.txt_1`…`pid.txt_4`), never the bare filename. This shows up in
`~/.trace/traceLog.txt` (under the device hash directory) at the end of
*every* job:

```
[Common.pm] unable to open file : .../DefaultBackupSet/pid.txt No such file or directory
[&backup] Operation could not be completed. Reason: unexpected_error
```

It fires on essentially every hourly CDP sync (near-100% of the time — this
is normal background noise) and, intermittently, on the nightly Scheduled
backup too, apparently more likely the longer the job runs (wider race window
against the CDP file-watcher's `pid.txt` rotation). **The file transfer
itself usually already completed successfully before this hits** — don't
trust the reported status; check the run's actual `[SUMMARY]` instead:

```bash
H=$(ls /opt/IDrive360/idriveIt/user_profile/scott | grep -v '\.' )   # current device hash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/$H"

ls -t "$PROFILE/Backup/DefaultBackupSet/LOGS" | head -1              # latest run
tail -40 "$PROFILE/Backup/DefaultBackupSet/LOGS/<latest-from-above>" # check [SUMMARY]
```

A `[SUMMARY]` showing real files backed up, with failures limited to the
usual permission-denied noise (`/etc/shadow`, `/etc/sudoers`,
`/pool/borg/*` — root-owned, `scott` can't read them, present in *every*
single run) means the backup itself is fine and the `Failure` status is just
this reporting bug — safe to disregard that Wazuh alert.

If `Files backed up now` is 0, or the failed-file list includes real source
files outside that standard root-owned set, that's a genuine failure —
investigate normally (stale-locks section above, or `journalctl -u idrive360cron`).

Reported to IDrive support; no fix as of 2026-08-10.

**Wazuh now surfaces this directly**, so you don't have to SSH in to check:
`/usr/local/bin/wazuh-idrive360-status` (source of truth:
[`nas01-backup-setup.sh`](../hosts/nas01/nas01-backup-setup.sh)) parses the
most recent run's log — Scheduled/Manual or CDP, whichever is newer — and
appends `files_backed_up=`, `size_backed_up=`, and `files_failed=` to the
`idrive360_backup:` line alongside `status=`, e.g.:

```
idrive360_backup: status=Failure time=1786392706 files_backed_up=66 size_backed_up=1.14GB files_failed=34 log=1786392003_Failure_Scheduled
```

So a `status=Failure` line with real `files_backed_up`/`size_backed_up`
numbers and only the usual `files_failed` noise can be triaged from the
Wazuh alert alone. The decoder/rule side that parses these fields on the
manager lives in the separate `wazuh-tailscale` repo (`log01`, reachable
over SSH), not this one — `decoders/idrive360-command.xml` and
`rules/idrive360-command-rules.xml` there have been updated to match, so
the Security Events dashboard alert *description* itself now reads e.g.
`IDrive360 backup FAILED — files_backed_up=66 size=1.14GB files_failed=34`,
not just the raw log line.

While fixing that, found the same alert-description bug (`$(agent.name)`
and a wrong `$(data.X)` field-reference prefix, both silently rendering
blank — confirmed via `wazuh-logtest`) pre-existing across
`borg-rules.xml`, `borg-restore-rules.xml`, `tailscale-health-rules.xml`,
and `nas01-health-rules.xml` too, unrelated to idrive360 specifically.
Fixed there as well; see that repo's commit history for details.

---

## Logs

```bash
# Live service log
journalctl -u idrive360cron -f

# IDrive360 internal logs
ls /opt/IDrive360/idriveIt/user_profile/scott/
find /opt/IDrive360 -name '*.log' 2>/dev/null
```

---

## Key paths (inside the VM)

| Path | Contents |
|---|---|
| `/opt/IDrive360/` | Agent install: binary, engine, libraries |
| `/opt/IDrive360/idriveIt/user_profile/scott/` | User profile, device registration, logs |
| `…/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE` | Backup engine lock — if stale, delete it |
| `…/Backup/DefaultBackupSet/LOGPID` | Path to active log; if stale, clear it |
| `…/Backup/DefaultBackupSet/LOGS/` | Per-run logs named `<timestamp>_<Status>_<type>` |
| `…/.userInfo/lastBackupStatus.txt` | JSON: last job status (Failure / Success / Running) |
| `/etc/idrive360crontab.json` | Active job schedule (written by agent) |
| `/pool` | ZFS data via virtiofs — backup source |
| `/mnt` | Auxiliary mounts via virtiofs — backup source |

## Host paths (on nas01)

| Path | Contents |
|---|---|
| `/var/lib/libvirt/images/nas01-backup.qcow2` | VM disk (persistent) |
| `/var/lib/libvirt/images/nas01-backup-cidata.iso` | Cloud-init seed ISO (used on first boot) |
| `/etc/nas01-backup/domain.xml` | libvirt VM definition |
| `/etc/nas01-backup/setup.sh` | One-time VM setup script |
