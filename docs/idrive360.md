# IDrive360 on nas01 — Operations Reference

IDrive360 runs inside an `ubuntu:24.04` Docker container managed by NixOS/systemd.
All CLI access goes through `docker exec`. The web console is at
[idrive360.com/enterprise/login](https://www.idrive360.com/enterprise/login).

**Device user hash**: `yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h`
(appears in many CLI commands as the device/account identifier)

---

## Container management

```bash
# Is the container up?
docker ps | grep idrive360

# What processes are running inside?
docker exec idrive360 ps aux

# Tail live logs (daemon output, backup progress, errors)
journalctl -u docker-idrive360 -f

# Last 100 lines of logs
journalctl -u docker-idrive360 -n 100

# Start / stop / restart the container
sudo systemctl restart docker-idrive360    # stops any in-progress backup
sudo systemctl stop   docker-idrive360    # stays down until manually started
sudo systemctl start  docker-idrive360

# Drop into a shell inside the container
docker exec -u scott -it idrive360 bash
docker exec -it idrive360 bash            # as root
```

> The container is configured `Restart=always` with a 60 s delay — use
> `systemctl stop` (not `docker stop`) to keep it down.

---

## How to run IDrive360 CLI commands

The main binary is `/opt/IDrive360/idrive360` (an Electron app, not Perl scripts).
All backup/status operations run **as user `scott`** inside the container.

General form:

```bash
docker exec -u scott -it idrive360 /opt/IDrive360/idrive360 <flag> [args]
```

To explore sub-commands, check what flags are referenced in the live crontab:

```bash
docker exec idrive360 cat /etc/idrive360crontab.json
```

---

## Known CLI commands (extracted from live crontab)

These are the exact commands IDrive360 runs internally — confirmed from
`/etc/idrive360crontab.json` on this machine.

### Run a scheduled backup

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --backup SCHEDULED \
  yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h
```

### Stop / terminate a backup job (the key command)

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --terminate-job backup - 2
```

`backup` is the job type; `2` is the backup set index (default_backupset = 2).
Run this when the web console shows a job as "running" but nothing is uploading.

### Run a CDP (continuous data protection) backup

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --backup CDP \
  yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h
```

### Rescan the backup set (re-index what files to back up)

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --utilities --rescan-backup-set 01 1783910457
```

### Check for / install updates

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --install update
```

### Background services (started by the cron daemon automatically)

```bash
# Watcher service — monitors for changes
/opt/IDrive360/idrive360 --utilities --watcher-service

# DB writer service
/opt/IDrive360/idrive360 --utilities --db-writer-service

# CDP server / client
/opt/IDrive360/idrive360 --cdp-server
/opt/IDrive360/idrive360 --cdp-client

# Python dashboard / status service
/opt/IDrive360/Idrivelib/dependencies/python/idrive360 start
```

These run automatically; don't start them manually unless debugging.

---

## Stop all backup jobs

### Option 1 — terminate-job (clean stop, tells the server)

```bash
docker exec -u scott -it idrive360 \
  /opt/IDrive360/idrive360 --terminate-job backup - 2
```

Check `ps aux` inside the container to confirm the backup subprocess is gone.

### Option 2 — kill the backup process directly

```bash
# Find the backup subprocess (look for --backup or idevsutil_dedup)
docker exec idrive360 ps aux

# Kill it (replace <PID>)
docker exec idrive360 kill <PID>
```

### Option 3 — restart the container (blunt but reliable)

Stops everything immediately. The container comes back in ~60 s without resuming
the stopped job. The web console will briefly show the device offline.

```bash
sudo systemctl restart docker-idrive360
journalctl -u docker-idrive360 -f    # watch it come back up
```

---

## Troubleshooting: job shows "running" in web console but nothing is uploading

This is a known IDrive360 state-sync issue — the server thinks a job is active
but the agent process has exited or stalled.

**Confirm the job is a phantom:**

```bash
docker exec idrive360 ps aux
```

If you only see the cron daemon and its background services (watcher, db-writer,
cdp-server, cdp-client, python) but no `--backup` subprocess, nothing is running.

**Fix sequence:**

1. Run `--terminate-job` to clear the server-side state:
   ```bash
   docker exec -u scott -it idrive360 \
     /opt/IDrive360/idrive360 --terminate-job backup - 2
   ```

2. If that doesn't clear it in the web console after ~2 minutes, restart the
   container:
   ```bash
   sudo systemctl restart docker-idrive360
   ```

3. If the console still shows it running, use the web console's **Stop Backup**
   button to force-clear it server-side, then retry from CLI.

---

## Troubleshooting: backup stuck since a specific date (stale lock files)

**Root cause (seen Jul 13 2026):** A backup crash leaves behind stale lock files.
The engine sees `ENGINE_LOCKE_FILE` + a non-empty `LOGPID` pointing to a
`Running_Scheduled` log and refuses to start any new job, forever. The web console
shows the old date as "in progress." A corrupted config (`CONFIGURATION_FILE.corrupt-<date>`)
in the profile directory is a telltale sign this happened.

**Diagnose:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h"

# Stale engine lock — date should match when the backup last "ran"
docker exec -u scott idrive360 ls -la "$PROFILE/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE"

# Stale running log reference
docker exec -u scott idrive360 cat "$PROFILE/Backup/DefaultBackupSet/LOGPID"

# Corrupted config marker
docker exec -u scott idrive360 ls "$PROFILE/CONFIGURATION_FILE.corrupt-"* 2>/dev/null

# Last backup status (should say Failure, not Running)
docker exec -u scott idrive360 cat "$PROFILE/.userInfo/lastBackupStatus.txt"
```

**Fix — clear stale locks and restart:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h"
LOGS="$PROFILE/Backup/DefaultBackupSet/LOGS"

docker exec -u scott idrive360 bash -c "
  # Remove the stale engine lock
  rm -f '$PROFILE/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE'

  # Clear stale PID and running-log pointer
  echo '' > '$PROFILE/Backup/pid.txt'
  echo '' > '$PROFILE/Backup/DefaultBackupSet/LOGPID'

  # Rename any Running_Scheduled log to Failure so the dashboard reflects reality
  for f in \$LOGS/*_Running_Scheduled; do
    [ -f \"\$f\" ] && mv \"\$f\" \"\${f/_Running_/_Failure_}\" && echo \"Renamed: \$f\"
  done
"

# Restart so the agent re-initializes with clean state
sudo systemctl restart docker-idrive360

# Once the container is back up (~60 s), trigger a backup manually to verify
docker exec -u scott idrive360 \
  /opt/IDrive360/idrive360 --backup SCHEDULED \
  yms8amixgppkylvghwrgdi7opkorvwyn3gjonvt7ditg7nu06h
```

---

## Troubleshooting: device shows offline, PermissionError in dashboard.log

**Symptom**: `dashboard.log` contains `PermissionError(13, 'Permission denied'): '/etc/idrive360crontab.json'`
and the device goes offline shortly after each container start.

**Root cause**: The Python scheduler (`idrivescheduler.py`) runs as `scott` (uid 1000) and
needs write access to `/etc/idrive360crontab.json` to update `nextschedule` timestamps.
If the file is root-owned (happens after a fresh `dpkg -i` bootstrap), the write fails,
the WebSocket connection closes, and the device shows offline.

**Fix** (already in the entrypoint): The entrypoint runs `chown scott:scott /etc/idrive360crontab.json && chmod 664`
before starting the cron daemon. If you see this error, verify the entrypoint has those lines
or run them manually:

```bash
docker exec idrive360 sh -c "
  chown scott:scott /etc/idrive360crontab.json
  chmod 664 /etc/idrive360crontab.json
"
sudo systemctl restart docker-idrive360
```

---

## Known log warning — not an error

```
Argument "*" isn't numeric in subroutine entry at &cron line 1.
```

This warning appears every scheduled interval and is harmless — it's a Perl
cron-parsing quirk in the IDrive360 vendor code when job schedules use `h: "*"`.
It does NOT mean the backup failed. If the daemon exits after this warning,
systemd restarts it within 60 s.

---

## Crontab / schedule

IDrive360 keeps its job schedule in two places (both must agree):

| Path | Scope |
|---|---|
| `/etc/idrive360crontab.json` | Ephemeral (in-container) — active schedule read by the daemon |
| `/opt/IDrive360/crontab.bak` | Persistent (host volume) — restored into `/etc/` on container restart |

The entrypoint copies `crontab.bak → /etc/idrive360crontab.json` on each container
start, so schedule changes made via the web console persist across container recreations.

```bash
# Current active schedule (raw JSON)
docker exec idrive360 cat /etc/idrive360crontab.json

# Persistent backup of schedule
docker exec idrive360 cat /opt/IDrive360/crontab.bak
```

**Backup schedule** (from current crontab): configured as **hourly at minute :42** in the web console,
status: `enabled`. **However, this schedule never runs** — see the known bug below.

**Backup set** (from `BackupsetFile.enc.json` as of 2026-07): `/home/`, `/var/`, `/mnt/` (empty — WD drives),
`/opt/` (empty — IDrive volume itself). **/pool is NOT included** — the ZFS pool data
(Borg repos, Syncthing) must be added via web console → Backup Settings.

---

## Known bug: hourly schedule crashes the cron daemon — backups never run

**Symptom**: the container restarts every ~59 minutes; no backup logs newer than the last
successful run; web console shows the device online but jobs stuck or stale.

**Root cause**: the vendor Perl cron daemon crashes with `Argument "*" isn't numeric`
when it tries to fire a job whose `h` field is `"*"` (the value set by the "hourly"
frequency). The crash happens at minute :42 (the scheduled minute) of the first hour
after container startup, killing the entire container.

**Fix: change the schedule to daily** in the IDrive360 web console:

1. Log in → **Backup** → **Schedule** for the default backup set
2. Change frequency from **Hourly** to **Daily** and pick a specific time (e.g., 8:00 PM)
3. Save — the web console pushes the change to the agent, which writes `h: "20"` (numeric)
   into `crontab.bak`. On the next restart the numeric hour is loaded and the Perl
   scheduler no longer crashes.

> Do NOT try to patch `crontab.bak` manually while the container is running — the cron
> daemon overwrites it on exit. Change it via the web console or stop the container first.

---

## Logs

```bash
# Live daemon log (primary source)
journalctl -u docker-idrive360 -f

# IDrive360 internal logs (inside the container)
docker exec -u scott idrive360 ls /opt/IDrive360/idriveIt/user_profile/scott/
docker exec -u scott idrive360 find /opt/IDrive360 -name '*.log' 2>/dev/null
```

---

## Key paths

| Path (host) | Path (container) | Contents |
|---|---|---|
| `/var/lib/idrive360/opt` | `/opt/IDrive360` | Agent state, device registration, crontab, logs |
| `/var/lib/idrive360/seed` | `/seed` | Installer `.deb` and rescued `idrive360cron` binary |
| `/pool` | `/pool` | ZFS data — read-only backup source |
| `/mnt` | `/mnt` | Auxiliary mounts — read-only backup source |
| — | `/opt/IDrive360/idriveIt/cache/` | PID file, user token, account JSON |
| — | `/etc/idrive360crontab.json` | Ephemeral active job schedule |
| — | `/opt/IDrive360/crontab.bak` | Persistent copy of job schedule |
| — | `…/Backup/DefaultBackupSet/ENGINE_LOCKE_FILE` | Backup engine lock — if stale, delete it |
| — | `…/Backup/DefaultBackupSet/LOGPID` | Path to active log; if stale, clear it |
| — | `…/Backup/DefaultBackupSet/LOGS/` | Per-run logs named `<timestamp>_<Status>_<type>` |
| — | `…/FAILED_UPLOAD/` | Failed backup reports (XML + log) |
| — | `…/CONFIGURATION_FILE.corrupt-<date>` | Left behind on config corruption — sign of a crash |
| — | `…/.userInfo/lastBackupStatus.txt` | JSON: last job status (Failure / Success / Running) |
