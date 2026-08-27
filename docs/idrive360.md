# IDrive360 on nas01 — Operations Reference

IDrive360 runs inside the `nas01-backup` QEMU/KVM VM (Ubuntu 24.04).
All CLI access goes through SSH into the VM. The web console is at
[idrive360.com/enterprise/login](https://www.idrive.com/enterprise/login).

**Device user hash**: `he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets`
(appears in many CLI commands as the device/account identifier; this changes if
the device is ever re-registered — confirm the current value with
`ls /opt/IDrive360/idriveIt/user_profile/scott/` before trusting the examples below)

**⚠️ There can be more than one device identity on disk at once.** IDrive360
ties backup history to a `device_id`/`MUID` generated at enrollment time — not
to the VM itself. If the VM is ever rebuilt/restored in a way that triggers a
fresh enrollment (this happened around 2026-08-20, likely during a hardware
migration), the *new* identity has zero backup history, while the *old* one
(`he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets` — confirmed current as
of 2026-08-26) still owns everything actually backed up so far. Before trusting
any device hash you find on disk, cross-check it against the MSP API
(below) — don't assume the newest-looking enrollment is the right one.

**✅ Resolved 2026-08-27** (was: GUI login stuck forever on "Connecting...",
sometimes preceded by "Your account is cancelled. Contact your
administrator."). Root cause turned out to be a **client-side bug in the
1.4.0 GUI's login handler**, not the account or network: using Chrome
DevTools Protocol (`idrive360-client --remote-debugging-port=9222`) to
inspect the app's own internal state, the actual login response object was
`{"LoginResp":{"message":"Password decoding failed"}, "userInfo": {...}}` —
identical whether the real password or a deliberately wrong throwaway
password was typed, and identical regardless of local config state. The
failure happened before any credential was ever sent to IDrive's servers,
and the GUI never surfaced this message to the user — it just hung on
"Connecting..." forever. **Fix that actually worked**: a clean
`apt remove` + reinstall of the same 1.4.0 `.deb` (again preserving the
existing `.device_id`/`.uuid_cache` so it reattached to the existing device
rather than creating a new enrollment — see warning above). Whatever local
Electron/renderer state was wedged, the reinstall cleared it; login,
`idrive360cron`, and scheduled backups are all confirmed working again
(check via the MSP API section below — `backup_status: "In Progress"` with
a fresh `last_backup` timestamp is the tell). Full writeup and diagnostic
technique (including the CDP approach and the real `CONFIGURATION_FILE`
encoding, which we'd previously misdiagnosed as corrupted — see Problem 1
below) is in `idrive360-support-ticket-2026-08-27.md` in this same
directory. If this recurs: don't bother re-debugging the password-decode
path from scratch, just try a clean reinstall first — it's a five-minute
fix and worked immediately last time.

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

## Manually installed packages (VM is Ubuntu — not declarative, not tracked anywhere else)

Unlike the NixOS hosts, `nas01-backup` has no flake/module manifest, so
anything installed here via `apt` only exists as installed state on the VM
disk — this doc is the only record. Sudo is passwordless for `scott` on this
VM (`(ALL) NOPASSWD: ALL`), so it's easy to install things ad hoc; keep this
list current when that happens.

| Package | Installed | Why | Pulled in as deps |
|---|---|---|---|
| `tshark` | 2026-08-27 | Debugging the IDrive360 login hang — decrypted the client's own HTTPS traffic (via Chromium's `SSLKEYLOGFILE`) to confirm no real login request was ever being sent | `wireshark-common`, `libwireshark17t64`, `libwireshark-data`, and their transitive libs (`libssh-gcrypt-4`, `libnghttp3-3`, `libsbc1`, `libsmi2t64`, `libbcg729-0`, `libcares2`, `libspandsp2t64`, `liblua5.2-0`, `libopencore-amrnb0`, `libwsutil15t64`, `libwiretap14t64`) |
| `epiphany-browser` | 2026-08-27 | Needed a system browser so Claude Desktop's "Continue with Google" (which hands off OAuth to the system default browser — see below) had somewhere to go | — |

`tcpdump` was already present on the base Ubuntu image — not something we
added.

Note: `tshark` was installed non-interactively (`DEBIAN_FRONTEND=noninteractive`),
which skips the debconf prompt that normally creates a `wireshark` group for
non-root packet capture. No such group exists on this VM — `tshark`/`tcpdump`
here only work via `sudo`.

**⚠️ `epiphany-browser` (WebKitGTK) crashes on any page load in this VM,
including `about:blank`** — not a network/content issue, a fatal trap inside
`libglib-2.0.so` itself (`dmesg`: `trap int3 ... in libglib-2.0.so`),
happening even with `LIBGL_ALWAYS_SOFTWARE=1`,
`WEBKIT_DISABLE_COMPOSITING_MODE=1`, `WEBKIT_DISABLE_DMABUF_RENDERER=1`
(this last one is set system-wide in `/etc/environment` — helps with an
unrelated DRI3 warning but doesn't fix the crash), and
`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` all set. CPU is
`host-passthrough` (not a feature-mismatch issue), plenty of free RAM after
closing other GUI apps — root cause not found. For contrast, this VM's two
Electron/Chromium apps (`idrive360-client`, and `claude-desktop` while it was
installed) never had this problem — the crash is specific to WebKitGTK here.
We tried Google Chrome (`google-chrome-stable` .deb, no snap) as a
workaround and it worked immediately (clean login page, no crashes), but it
was removed at the user's request (OAuth-via-Google wasn't worth the
hassle) along with `claude-desktop` itself — Claude Desktop login on this VM
is parked, not solved. If revisited: either root-cause the epiphany/glib
trap, or reinstall `google-chrome-stable` (same steps as `claude-desktop`
below, just Google's official `.deb` from
`https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`)
and set it as default browser (`xdg-settings set default-web-browser
google-chrome.desktop`).

Neither is required for normal IDrive360 operation; both are safe to
`apt remove tshark` (and its now-orphaned deps via `apt autoremove`) if you'd
rather not have a packet-capture toolchain sitting on a backup VM long-term.

---

## Checking status via the IDrive360 MSP API

Faster/more authoritative than reading local logs, since it's the server's own
view — use this first when triaging.

- Base URL: `https://api.idrive360.com/api/msp`
- Auth: `Authorization: Bearer <api-key>` header
- API key: stored in Bitwarden, **not** in this repo — grab it from there,
  never commit it
- Docs: https://www.idrive.com/endpoint-backup/api-collections

```bash
curl -s -H "Authorization: Bearer $IDRIVE360_API_KEY" \
     -H "Content-Type: application/json" \
     "https://api.idrive360.com/api/msp/device/summary"
```

Returns a JSON array, one entry per device on the account:
`device_id`, `status` (`online`/`offline`/`blocked`/`archived`),
`backup_status` (`Success`/`Failure`/`In Progress`/`Cancelled`),
`last_backup`, `next_backup` (both ISO timestamps), `backup_failure_reason`.

There is **no documented endpoint to trigger an on-demand backup** — only
plan/status management. To force a backup, use the local CLI
(`--backup CDP <id>` / `--backup SCHEDULED <id>`) — see below.

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
installer drops `~/.config/autostart/idrive360client.desktop`, which LXDE
runs automatically every time scott's console session (auto-)starts.

**Manually edited (2026-08-24)**: removed `--hidden` from that file's `Exec=`
line (originally `idrive360-client --hidden`). Since this VM's only purpose
is running IDrive360, there's no reason to hide the window — the console
(`idrive-console-vnc`) is only ever opened to look at this app. This is a
vendor-installed file, not managed by `nas01-backup-setup.sh`, so it won't
survive a fresh install from that script — only a full disk restore (see
[nas01.md](nas01.md#vm-disk-backup-and-restore)) preserves it. If IDrive360
is ever reinstalled from scratch, redo this by editing
`~/.config/autostart/idrive360client.desktop` to drop `--hidden`.

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

### Check job status (reliable — talks to the real backend)

```bash
/opt/IDrive360/idrive360 --job-status
```

Prints real quota (`Storage Used: X GB of Y GB`) and either
`Unable to find any active job.` or details of a running one. Unlike
`--backup CDP/SCHEDULED <id>` (below), this one reliably produces output —
good first check to confirm the binary can actually reach IDrive's servers at
all before chasing anything else.

### Manually trigger a backup

```bash
/opt/IDrive360/idrive360 --backup CDP <device-id>          # continuous
/opt/IDrive360/idrive360 --backup SCHEDULED <device-id>    # full/scheduled
```

**Gotcha 1 — no useful output over a non-interactive SSH session**: both this
and `--job-status` are interactive TUI progress displays (they call
`stty`/`tput`). Over `tailscale ssh ... "command"` (no real TTY) they don't
exit — they loop indefinitely, spamming `TERM environment variable not set`,
`stty: 'standard input': Inappropriate ioctl for device`, etc. Real data does
land in there between the noise (e.g. `--job-status` printed
`Storage Used: X GB of Y GB` and `Preparing File list...` before the spam
started), but don't wait for it to return — it won't. Give it a few seconds,
grab what you need from the captured output, then kill it (the local
`tailscale ssh` client can be stopped freely; the remote process it spawned
is independent and will keep running/looping — kill it on the VM directly by
PID if you want it gone, e.g. `pkill -f 'idrive360 --job-status'`).

**Gotcha 2 — a second invocation while a job is already running doesn't
queue, it defers silently**: if a backup is already active (e.g. one you
started from the web console), invoking `--backup SCHEDULED <device-id>`
again does *not* launch a second job. It updates
`Backup/pid.txt` to point at the new process's own PID, but the actual
`Backup/DefaultBackupSet/BackupsetFile.enc.json.lock` stays held by the
original job's `--utilities --db-writer-service` PID, and the new process
just sits idle (~0% CPU) forever without spawning any `idevsutil_dedup`
workers of its own. Check `cat .../Backup/DefaultBackupSet/BackupsetFile.enc.json.lock`
against `ps` to see which PID actually owns the running job before assuming
your trigger did nothing — it may just mean a backup was already in flight.

**Gotcha 3**: with a valid `<device-id>` and no job already running, these
exit 0 with **zero output** whether they actually did something or silently
no-op'd — the only way to tell is to check `ps` for new `idevsutil_dedup`
worker processes and tail the newest file in
`.../Backup/DefaultBackupSet/LOGS/`. If nothing happens, it's almost always a
stale lock file (see the corrupted-state-files section below) — check that
before assuming the command itself is broken.

Without a device-id, `--backup CDP` / `--backup SCHEDULED` print
`Incorrect Backup Type in CONFIGURATION_FILE.` — that's the type-check
failing, not a launch failure; it's not diagnostic of anything, just confirms
the flag itself is recognized.

### `--rescan-backup-set` isn't a general rescan trigger

It looks like the obvious "force a rescan" flag but it's CDP-specific: it
re-syncs the real-time file-watch list (`cdpRescan()` internally), and its
args are a day-interval + start-time pair meant to be invoked periodically by
cron, not a one-shot "walk the folders now." To force a full walk of every
folder in the backup set (which is what you want after adding a new folder
to the plan, e.g. `/pool/syncthing`), use `--backup SCHEDULED <device-id>`
above instead — see Gotcha 2 if one's already running.

### Discovering other CLI flags

`--help`/`--usage` produce no output on this build. `strings` isn't installed
on this Ubuntu image (`binutils` missing) — use `grep -a` instead:

```bash
grep -a -oE '\-\-[a-z][a-z-]{2,25}' /opt/IDrive360/idrive360 | sort -u
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

## Troubleshooting: device shows offline / GUI crash-loops / nothing uploads (corrupted state files)

**Symptom**: web console shows a job "In Progress" but the device itself
shows offline (or via API: `status` is `offline`, or `backup_status` stuck on
`Failure` with an old `last_backup`). Locally: `idrive360-client` GUI
launches then quits within seconds/minutes every time; `traceLog.txt` fills
with `Unable to start CDP client server` repeating every few seconds;
`idrive360cron.service` restarts itself every few minutes for no obvious
reason (`journalctl -u idrive360cron` shows repeated Started/Stopped with no
real gap).

This happened 2026-08-26 and took most of a session to fully root-cause. Two
independent problems, usually present together:

### Problem 1 — ~~corrupted vendor state files~~ (misdiagnosis — see correction)

**⚠️ Correction (2026-08-27): this was a misdiagnosis.** The files below are
**not** plain base64 — decoding them with plain base64 (as the snippet
originally here did) produces exactly the "interleaved garbage" pattern that
looked like corruption. The real encoding (reverse-engineered from an older
CLI-based client's Perl source, `Common.pm::encryptString`/`decryptString`)
is: **base64-encode, then swap the first quarter of the resulting string
with the last quarter** (the middle half stays in place). Decoding correctly
(swap back, then base64-decode) showed the "corrupted" files on
`nas01-backup` were actually fully valid, correct JSON the whole time. If
you hit garbled-looking output from one of these files, decode it properly
before assuming corruption:

```bash
# Correct decode (Perl, using the vendor's own algorithm)
perl -MMIME::Base64 -e '
  local $/; my $s = <STDIN>; chomp($s);
  my $n = length $s; my $sw = $n - ($n % 4); my $sh = $sw/4;
  my $a = substr($s, 0, $sh); my $b = substr($s, (3*$sh), $sh);
  substr($s, (3*$sh), $sh) = $a; substr($s, 0, $sh) = $b;
  print decode_base64($s);
' < CONFIGURATION_FILE

# Correct re-encode (for patching a field and writing back)
perl -MMIME::Base64 -e '
  local $/; my $s = <STDIN>;
  $s = encode_base64($s); chomp($s);
  my $n = length $s; my $sw = $n - ($n % 4); my $sh = $sw/4;
  my $a = substr($s, 0, $sh); my $b = substr($s, (3*$sh), $sh);
  substr($s, (3*$sh), $sh) = $a; substr($s, 0, $sh) = $b;
  print $s;
' < patched.json > CONFIGURATION_FILE.new
```

Applies to: `CONFIGURATION_FILE` (both the per-account copy and the
top-level `user_profile/scott/CONFIGURATION_FILE`), `BACKUPID_FILE`. Files
under `.userInfo/` (`IDPWD`, `IDPWD_SCH`, `IDENPWD`) use a *different*
mechanism (the vendor's `idevsutil` binary's own `STRINGENCODE` operation,
not `encryptString`) — don't try to decode those with the algorithm above.

If a file genuinely doesn't decode even with the correct algorithm (decode
throws, or the result isn't valid JSON), *then* it's real corruption — pull
a clean copy from a Borg VM-disk backup that predates the corruption (see
the next section for how, without doing a full VM restore), or, failing
that, hand-reconstruct as a last resort (slow, error-prone, risks recovering
a stale value for a field that changes often like an auth `TOKEN` or
`nextschedule` timestamp).

See `idrive360-support-ticket-2026-08-27.md` for the full story: what
actually turned out to be broken (2026-08-27) was a client-side
"Password decoding failed" bug in the 1.4.0 GUI's login handler, unrelated
to these state files — fixed by a plain reinstall. Don't assume every
"IDrive360 broken" symptom is state-file corruption; check with the CDP
technique documented there first.

### Problem 2 — stale lock files (separate from the `ENGINE_LOCKE_FILE`/`LOGPID` pair documented above)

**Root cause**: several *other* lock files hold a bare PID and are never
validated against `ps` before being trusted — if that PID no longer exists
(process died uncleanly, or the VM rebooted without a graceful shutdown), the
app still treats the lock as held and silently refuses to proceed, with
**no error message at all**. This is what made CDP never start even after
Problem 1 was fixed: `CDP/watcher.lock` and the top-level `cron.lock` both
pointed at PIDs from before the last reboot. Same story for
`Backup/DefaultBackupSet/BackupsetFile.enc.json.lock` — a stale copy of that
one silently blocks `--backup CDP/SCHEDULED <id>` from doing anything (exit 0,
zero output, no new process, nothing in the trace log).

**Diagnose:**

```bash
PROFILE="/opt/IDrive360/idriveIt/user_profile/scott/<device-id>"
for f in "$PROFILE/CDP/watcher.lock" \
         /opt/IDrive360/idriveIt/user_profile/cron.lock \
         "$PROFILE/Backup/DefaultBackupSet/BackupsetFile.enc.json.lock"; do
  pid=$(cat "$f" 2>/dev/null)
  [ -n "$pid" ] && ! ps -p "$pid" >/dev/null 2>&1 && echo "STALE: $f -> dead PID $pid"
done
```

**Fix:**

```bash
sudo systemctl stop idrive360cron.service
sudo -u scott rm -f "$PROFILE/CDP/watcher.lock" \
                     /opt/IDrive360/idriveIt/user_profile/cron.lock \
                     "$PROFILE/Backup/DefaultBackupSet/BackupsetFile.enc.json.lock"
sudo systemctl start idrive360cron.service
```

Then retry `--backup CDP <id>` / wait for the next scheduled run and confirm
via `ps` (new `idevsutil_dedup` workers) or `--job-status`.

### Recovering a specific file from a Borg VM-disk backup without a full restore

`idrive-vm-restore` (on nas01) swaps the *entire* VM disk — it also reverts
anything else done inside the guest since that backup (autologin config,
etc.) and, worse, can land you on a **stale device enrollment** if the
corruption predates every recent nightly backup (it did, here — see the
device-identity warning up top). Prefer extracting just the files you need:

```bash
# On nas01 (needs sudo password — not passwordless):
REPO=/pool/borg/nas01
ARCHIVE=nas01-system-YYYY-MM-DDTHH:MM:SS   # pick one from: borg list $REPO
DOMAIN=nas01-backup

export BORG_PASSCOMMAND="cat /run/bitwarden-secrets/borg_passphrase"
sudo mkdir -p /tmp/vm-extract && cd /tmp/vm-extract
sudo env BORG_PASSCOMMAND="$BORG_PASSCOMMAND" borg extract \
  "$REPO::$ARCHIVE" "var/lib/libvirt/images/$DOMAIN.qcow2"

sudo modprobe nbd max_part=16
sudo qemu-nbd -c /dev/nbd8 --read-only \
  "/tmp/vm-extract/var/lib/libvirt/images/$DOMAIN.qcow2"
sudo lsblk -f /dev/nbd8                 # find the ext4 root partition

MNT=$(sudo mktemp -d)
# noload is required — mounting read-only still tries to replay the journal
# otherwise, which fails against a --read-only nbd device
sudo mount -t ext4 -o ro,noload /dev/nbd8p1 "$MNT"

# copy out just what you need, e.g.:
sudo cp -a "$MNT/opt/IDrive360/idriveIt/user_profile/scott" ~/idrive-extract/

sudo umount "$MNT"
sudo qemu-nbd -d /dev/nbd8
```

If you do end up needing a full `idrive-vm-restore`: **immediately** check
the restored disk's device-id against the MSP API (`device/summary`) before
letting `idrive360cron` run — an old-enough backup may predate the current
enrollment, or (less likely) may itself already contain the corruption.
Also expect to have to redo any live-guest-only fixes newer than the chosen
backup — check git-blame/dates in this doc and [nas01.md](nas01.md) for
what's been changed directly on the guest vs. what's declarative.

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
| `…/Backup/DefaultBackupSet/BackupsetFile.enc.json.lock` | Holds a PID; if dead, silently blocks all `--backup` triggers — delete if stale |
| `…/CDP/watcher.lock` | Holds a PID; if dead, blocks CDP server startup — delete if stale |
| `/opt/IDrive360/idriveIt/user_profile/cron.lock` | Top-level cron lock; holds a PID; if dead, blocks scheduled jobs — delete if stale |
| `…/CONFIGURATION_FILE`, `…/BACKUPID_FILE` | JSON state, encoded as base64-then-quarter-swapped (not plain base64 — see "Problem 1" below before assuming corruption) |
| `…/rememberme` | Auto-login state; presence/absence affects whether the GUI skips the login form |
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
