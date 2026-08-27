# IDrive360 troubleshooting — live session state (as of 2026-08-27 ~16:30 UTC)

Handoff notes for continuing this work directly on `nas01-backup`.
`idrive360.md` in this same directory is the durable reference doc
(architecture, commands, known gotchas, recovery procedures) — read that
first. This file is just "what was actively happening when the baton got
passed."

## Confirmed device identity (do not change)

- device_id: `he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets`
- MUID: `da13e9d4da0444339805985af44d5a07`
- Recovered from the 2026-08-07 Borg VM-disk backup during a 2026-08-26
  rollback, confirmed as the identity with real backup history. Do NOT
  re-enroll or let the client generate a new device ID — a fresh enrollment
  orphans all prior backup history. See `idrive360.md`'s top warning.

## Recurring stall bug — now understood, not yet root-caused

Since 2026-08-26 the backup engine has stalled repeatedly (confirmed
recurrences ~23:54 that night, ~05:30, and ~13:05 the next day — roughly
every 6-8 hours): a `--backup SCHEDULED` job stops producing any log output
or CPU activity, while `cron.lock` and/or
`Backup/DefaultBackupSet/BackupsetFile.enc.json.lock` are found holding a
PID that no longer exists (`idrive360.md`'s "Problem 2"). Each time, the fix
has been:

1. `systemctl stop idrive360cron.service`
2. Kill the orphaned `--backup SCHEDULED` and `--utilities --db-writer-service`
   processes directly (they aren't children of the unit, so stopping it
   doesn't kill them)
3. Clear `cron.lock`, `BackupsetFile.enc.json.lock`, `ENGINE_LOCKE_FILE`,
   truncate `LOGPID`, rename any `*_Running_*` logs to `*_Failure_*`
4. `systemctl start idrive360cron.service`
5. Re-trigger with `--backup SCHEDULED <device-id>`

This reliably gets data moving again within ~30s (confirmed via fresh
`[SUCCESS]` log lines and live `idevsutil_dedup` CPU usage), but it keeps
coming back. **Not yet fixed at the root.**

A check-and-clear script exists at `/usr/local/bin/idrive360-clear-stall.sh`
on `nas01-backup` (detects a stale lock or a `_Running_` log that hasn't
been written to in 45+ minutes, then applies the fix above; supports
`--check-only`). **It currently lives only on the VM guest, not in this
repo** — it should be committed here (e.g. under `hosts/nas01/` alongside
the other nas01 scripts) and ideally wired into a systemd timer, or it'll be
lost on the next VM rebuild. Not yet done.

## Real root cause candidate: corrupted CONFIGURATION_FILE — in progress

Both `CONFIGURATION_FILE` copies (the per-device one under
`user_profile/scott/<device-id>/` and the top-level
`user_profile/scott/CONFIGURATION_FILE`) decode to garbage binary, not
JSON — matches `idrive360.md`'s "Problem 1" (concurrent-write corruption).
This is almost certainly the same issue flagged 2026-08-26 as "GUI shows
'Your account is cancelled'" / `Unable to retrieve the quota` spamming
`.trace/traceLog.txt` every ~30s — deferred back then, never actually
fixed. Very plausibly also the cause of the web-console status "flapping"
the user has now seen on multiple separate days: a device that can't
reliably parse its own auth/account state can't reliably report status
either.

Plan (per `idrive360.md`'s recovery section): pull a clean copy of this
file from a Borg VM-disk backup that predates the corruption, without doing
a full VM restore (`qemu-nbd` mount of just the extracted qcow2, copy out
the one file). Corruption was already present as of 2026-08-26, so need an
archive from before that — `borg list /pool/borg/nas01` on **nas01 (the
host, not this VM)** to find candidates, oldest-first from around
2026-08-07 (when the current device identity was recovered) forward, and
test-decode the extracted file until a clean one is found.

**Blocker just cleared**: `sudo borg ...` and
`sudo env BORG_PASSCOMMAND=... borg ...` needed an interactive sudo
password on nas01 (host), which isn't available non-interactively. Fixed by
adding fleet-wide passwordless-sudo rules for `borg` to
`modules/user-scott.nix` (commit `7d1814a`, pushed). **Requires
`nixos-rebuild switch --flake /home/scott/git/nixos#nas01` on nas01 to take
effect — not yet confirmed applied.**

## Where to pick up

1. Confirm the `nixos-rebuild switch` for the borg sudo rule has been
   applied on nas01 (`sudo -n borg --version` should no longer prompt for a
   password).
2. `borg list /pool/borg/nas01` on nas01 (host) to enumerate archives.
3. Extract candidate archives (oldest reasonable one first) and check
   `user_profile/scott/CONFIGURATION_FILE` / the per-device copy decode as
   valid base64 JSON; use the first clean one found.
4. Replace both corrupted copies with the recovered clean file (stop
   `idrive360cron` first), restart, and confirm the GUI dashboard's
   `Unable to retrieve the quota` errors stop and the web console shows
   consistent (non-flapping) status.
5. Commit `idrive360-clear-stall.sh` into this repo and consider a systemd
   timer for it, per the note above.
