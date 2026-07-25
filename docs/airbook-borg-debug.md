# airbook-darwin Borg backup: first-upload connection resets

> **STATUS: In progress (2026-07-22).** Fresh borg repo on nas01 (~35 GB
> home dir target). Every long-running `borg create` on airbook has died
> mid-transfer with `Read from remote host nas01.warthog-royal.ts.net:
> Connection reset by peer` — including the current attempt after all
> three mitigations landed (see [Attempt 3](#attempt-3--keepalives--caffeinate--verbose-2026-07-22)).

## Timeline

| When | Commit | State on nas01 | Outcome |
|---|---|---|---|
| 2026-07-21 17:25 | `9de0a1d` (auto-init) | Fresh repo, first `borg init` writes `config`/`README` | Ran ~30 min, first checkpoint committed at 17:56 (`index.71`), RST at 17:57 |
| 2026-07-21 19:56 / 20:34 | (post daemon-scripts rebuild) | No new transactions; only `nonce` touched | Both RST; run went 6+ hours with **zero** additional commits |
| 2026-07-22 02:29 (scheduled) | (post tailscaled cleanup, `247e5ce`) | Still frozen at index.71 | RST after several hours |
| 2026-07-22 20:26 | `a6d0653` + `2502ab4` (keepalives + caffeinate + `-v`) | Watching now | pending |

Repo transaction id has been frozen at **71** since 2026-07-21 17:56.
Only one checkpoint has ever been committed.

## What each attempt tried and why it wasn't sufficient

### Attempt 1 — auto-init (`9de0a1d`)
The passphrase on the old repo diverged from Bitwarden `.login.password`.
Fix: delete the repo on nas01 and let `borg init --encryption=repokey-blake2`
recreate it on first run. That worked — the first run got 32 GB uploaded
and one checkpoint before the connection died at 17:57.

### Attempt 2 — remove second tailscaled (`247e5ce`, `11ecf08`)
The box had **two Tailscale endpoints running side by side**:
- App Store macsys Tailscale.app (System Network Extension `io.tailscale.ipn.macsys.network-extension`, `[activated enabled]`)
- Brew `/usr/local/bin/tailscaled` daemon loaded by `com.tailscale.tailscaled.plist`

Both trying to own the utun interface and re-negotiating DERP. Removed
the brew standalone in favour of the sandboxed App Store version;
`ssh` server bootstrap and `authorized_keys` deployment removed at the
same time since Tailscale-SSH-server hosting was the only reason to have
the standalone daemon.

Trade-off accepted: no inbound SSH to airbook at all.

Result: Same `Connection reset by peer` symptom on the next borg run —
so the second tailscaled was **not** the primary cause (or wasn't the
only cause).

### Attempt 3 — keepalives + caffeinate + verbose (`2502ab4`)
Three changes to the borg-backup daemon script in
`hosts/airbook-darwin/default.nix`:

1. `BORG_RSH` gains keepalives:
   ```
   -o ServerAliveInterval=30
   -o ServerAliveCountMax=6
   -o TCPKeepAlive=yes
   ```
   Prevents NAT/router middleware from silently RST'ing a flow it thinks
   is idle, and detects a truly dead session in ~3 min instead of hours.

2. Wrap `borg create` in `/usr/bin/caffeinate -i`. `pmset -g` on airbook
   shows sleep assertions come and go (e.g. `AddressBookSourceSync`); we
   can't rely on another process to hold the display/idle-sleep gate for
   6+ hours.

3. `borg create -v` so future drops leave a per-file trail in
   `backup.log` — we can see which file/phase borg was in at the moment
   of disconnect.

Watching now via background waiter `bv3jzvhgt`.

## What we know for sure

- **nas01 side isn't dropping via sshd config.** `sshd_config` on nas01
  has no `ClientAlive*`, `MaxSessions`, `MaxSessionTime` — the resets are
  not policy-driven from that end.
- **Repo isn't locked.** `/pool/borg/airbook-darwin/lock.*` doesn't exist
  between runs; each attempt gets a clean lock.
- **Passphrase is correct.** Auto-init worked, and the initial 30 min of
  Attempt 1 successfully committed transaction 71.
- **Not a WiFi power-management setting alone.** `networksetup -getairportpower en0`
  shows Wi-Fi on; `pmset -g` shows `womp 1`, `powernap 1`, `sleep 1
  (sleep prevented by caffeinate, AddressBookSourceSync)`. Sleep is
  prevented by *some* process but not consistently by us.
- **borg auto-retry doesn't cover this.** `borg create` errors out fully
  on SSH drop; checkpoint archives only exist if a full transaction
  commits, which requires reaching the 30 min mark before an RST.

## Remaining hypotheses if Attempt 3 also fails

1. **Home router / ISP NAT** aggressively resetting long-lived TCP
   flows. Look at nas01's connections table during the next run:
   `sudo conntrack -L | grep <airbook-tailnet-ip>` or `ss -tanp`. A flow
   that goes idle for the connection-tracking timeout will be RST.
   Keepalives at 30s should already defeat this, but if the NAT timeout
   is <30 s, need to shorten.

2. **Tailscale MTU / fragmentation.** Long transfers over
   Tailscale's WireGuard tunnel can wedge on PMTU black holes; symptom is
   flow works briefly then hangs, then RST. Try
   `tailscale ping --tsmp nas01` and check for large-packet loss:
   `sudo ping -D -s 1400 nas01.warthog-royal.ts.net`.

3. **Firewall on nas01** (nftables/iptables) with a
   `state RELATED,ESTABLISHED` rule but a `conntrack` table
   filling up. `dmesg | grep 'nf_conntrack: table full'` on nas01.

4. **ZFS / storage backpressure on nas01.** If the `pool` gets IO-starved
   (borg check, scrub, or the IDrive360 container), borg-serve may block
   long enough that airbook's `ServerAliveCountMax` fires and airbook
   disconnects. Look at `zpool iostat 5` on nas01 during a run.

5. **Corrupt-state loop.** The frozen index.71 + 74 chunks means every
   run re-reads the same segments to negotiate resume. If `borg check`
   reveals inconsistency, a `borg break-lock` + `borg check --repair` may
   be needed. Run offline before the next attempt.

## Diagnostic commands to run if it dies again

```bash
# 1. Exact time of death from log
tail -30 /Users/scott/.local/share/borg/backup.log
tail -30 /Users/scott/.local/share/borg/backup.error.log

# 2. What was borg working on at the moment of drop (needs -v run)
grep -E '^A |^M |^U ' /Users/scott/.local/share/borg/backup.log | tail -5

# 3. Repo state on nas01
tailscale ssh nas01 'ls -la /pool/borg/airbook-darwin/; ls /pool/borg/airbook-darwin/data/0/ | wc -l'

# 4. Was a checkpoint committed?
BORG_PASSCOMMAND="cat /etc/wazuh/borg.pass" \
  BORG_RSH="ssh -i ~/.ssh/id_ed25519_legacy" \
  BORG_REMOTE_PATH=/run/current-system/sw/bin/borg \
  borg list ssh://scott@nas01.warthog-royal.ts.net/pool/borg/airbook-darwin

# 5. nas01 conntrack + zpool state
tailscale ssh nas01 'sudo dmesg | grep -i "conntrack table full" | tail; zpool iostat 1 3'
```

## Related nix-darwin quirks discovered

- **nixpkgs-unstable dropped x86_64-darwin at 26.11.** Must pin
  `nixpkgs-darwin` (26.05-darwin) as a separate flake input and align
  `nix-darwin` to the matching `nix-darwin-26.05` branch, or
  darwin-rebuild aborts with a version-mismatch assertion. See
  `flake.nix` inputs.
- **home-manager `programs.ssh.matchBlocks` → `programs.ssh.settings`**
  in 26.05. Straight rename; must also set
  `enableDefaultConfig = false` when you want to opt out of hm's
  implicit `Host *` block.
- **nix-darwin org moved** from `github:LnL7/nix-darwin` to
  `github:nix-darwin/nix-darwin` (LnL7 is now a mirror).
