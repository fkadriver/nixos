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

## Known log warning — not an error

```
Argument "*" isn't numeric in subroutine entry at &cron line 1.
```

This warning appears every scheduled interval and is harmless — it's a Perl
cron-parsing quirk in the IDrive360 vendor code. It does NOT mean the backup
failed. If the daemon exits after this warning, systemd restarts it within 60 s.

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

**Backup schedule** (from current crontab): runs **hourly**, every `*/42` minutes,
status: `enabled`. Cancel job is configured but `disabled`.

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
