Subject: Desktop client login fails ("Failed to get server address" / access denied) — device online per API, backup plan intact, fresh reinstall did not resolve

Account email: hoot-glowing24@icloud.com
Company ID: 36136
Device name: nas01-backup
Device ID: he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets
Backup plan: "Linux Servers" (backup set id 480395)
OS: Ubuntu 24.04 (KVM/QEMU guest)
Client version: 1.4.0 (auto-updated from 1.3.0 on 2026-08-27; issue predates the update)

Summary
-------
The IDrive360 desktop client cannot complete login on this device. The MSP
API (device/summary) shows the device as status "online" with an intact
backup plan, but the desktop client itself cannot authenticate — it hangs
indefinitely on "Connecting..." after a manual sign-in attempt, or (in an
earlier state, before we reset local credential caches) showed "Access to
the full suite desktop application is denied. Please contact your
administrator." The account's console/billing settings have been checked
and appear correct, with no cancellation or policy restriction visible on
our end.

Timeline
--------
- 2026-08-26 ~16:01 UTC: Desktop client's background session first starts
  failing a websocket reconnect with "Invalid close opcode" — recurring
  every 30-70s from this point forward, never once succeeding since. This
  is the earliest sign of trouble we can find, and predates everything
  below.
- 2026-08-26 ~23:50 UTC: A login attempt via the desktop GUI shows "Your
  account is cancelled. Contact your administrator."
- 2026-08-27 ~17:01 UTC: VM rebooted; client auto-updated 1.3.0 -> 1.4.0 in
  the process. Same symptoms persisted post-update.
- 2026-08-27: Confirmed via MSP API (device/summary) that the device shows
  status "online", backup_status alternating Success/Failure, and a real,
  named backup plan ("Linux Servers", id 480395) still attached — i.e. the
  backend clearly still recognizes this device and account.
- 2026-08-27: Performed a clean uninstall (apt remove) and reinstall of the
  1.4.0 .deb client, preserving the existing local device-identity cache
  (device_id he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets) so the
  reinstall would reattach to the existing device rather than creating a
  new enrollment. Same login failure persists on the fresh install.

What we've ruled out
---------------------
- Network/DNS/firewall: api.idrive360.com and wsn4.idrive360.com resolve
  correctly; TCP/TLS connections to the resolved IPs succeed and respond
  as expected (confirmed via curl and raw socket tests, including a raw
  banner grab from the EVS-related server on port 443 returning a valid
  "@IDEVSD" protocol response, not a connection failure).
- Local credential-file corruption: we found and worked around a real,
  separate, unrelated bug where several vendor state files
  (CONFIGURATION_FILE, rememberme, BACKUPID_FILE, notification.json, etc.)
  get corrupted by what looks like unsynchronized concurrent writes (byte-
  interleaved/spliced content, reproducible across multiple days and
  multiple nightly backups). We fully reinstalled the client and restored
  a clean local profile, which did not change the login outcome.
- Wrong device enrollment: verified via MSP API and manually corrected the
  local device-identity cache (.device_id / .uuid_cache under
  idriveIt/cache) before the reinstall's first launch, to ensure the
  client would reattach to the existing device_id rather than mint a new
  one. Confirmed post-reinstall that no new device folder was created.

Current failure signature (fresh install, correct device identity, manual
login submitted through the GUI with correct account credentials):
```
[Common.pm] EVS domain failed & need to retry with IP
[Common.pm] Failed to get server address.   (repeats every ~5 min)
```
No credential/session file (IDPWD, IDPWD_SCH, IDENPWD, rememberme) is ever
written locally when this happens — the login attempt appears to fail
before completing any handshake with the server, despite the underlying
network path being confirmed healthy.

Request
-------
Could you check this device/account on your end for anything stuck in a
bad session, entitlement, or policy state? Given the backend clearly still
recognizes the device (MSP API shows it online with an intact backup plan)
but the desktop client can never successfully authenticate — even after a
completely fresh install — this looks like something server-side rather
than a local software issue.

Happy to provide additional logs (trace logs, dashboard.log) on request.
