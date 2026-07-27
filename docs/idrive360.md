# IDrive360 on nas01 — Operations Reference

IDrive360 runs inside the `nas01-backup` QEMU/KVM VM (Ubuntu 24.04).
All CLI access goes through SSH into the VM. The web console is at
[idrive360.com/enterprise/login](https://www.idrive.com/enterprise/login).

**Device user hash**: `yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h`
(appears in many CLI commands as the device/account identifier)

---

## VM access

```bash
# SSH into the VM (from nas01)
idrive-ssh          # alias: ssh scott@$(virsh domifaddr nas01-backup | awk '/ipv4/{print $4}' | cut -d/ -f1)

# Serial console (Ctrl+] to exit)
idrive-console

# VM status / power
idrive-status       # virsh domstate nas01-backup
idrive-start        # sudo virsh start nas01-backup
idrive-stop         # sudo virsh shutdown nas01-backup
```

VNC from a remote Tailscale machine (e.g. Remmina):
```bash
# On the remote machine, open an SSH tunnel (keep this terminal open):
ssh -L 5901:192.168.122.54:5901 -N scott@nas01.warthog-royal.ts.net

# Connect Remmina to localhost:5901, password: changeme
# Disable Remmina's built-in SSH tunnel (Tailscale SSH is incompatible with libssh)
```

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
  yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h
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
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h"

ls -la "$PROFILE/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE"
cat "$PROFILE/Backup/DefaultBackupSet/LOGPID"
ls "$PROFILE/CONFIGURATION_FILE.corrupt-"* 2>/dev/null
cat "$PROFILE/.userInfo/lastBackupStatus.txt"
```

**Fix — clear stale locks and restart:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h"
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
