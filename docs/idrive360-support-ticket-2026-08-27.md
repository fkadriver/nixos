Subject: Desktop client (1.4.0) fails to log in — reproducible "Password decoding failed" internal error, never surfaced to the user, occurs for any password

Account email: hoot-glowing24@icloud.com
Company ID: 36136
Device name: nas01-backup
Device ID: he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets
Backup plan: "Linux Servers" (backup set id 480395)
OS: Ubuntu 24.04 (KVM/QEMU guest)
Client version: 1.4.0 (auto-updated from 1.3.0 on 2026-08-27; issue predates the update)

Summary
-------
The IDrive360 desktop client cannot complete login on this device. The UI
gets stuck on "Connecting..." indefinitely after a sign-in attempt and never
shows an error. Using Chrome DevTools Protocol to inspect the client's own
internal state (it's an Electron app), we found the actual login response
object the renderer receives from the app's login handler:

    {"LoginResp":{"desc":false,"message":"Password decoding failed"},
     "userInfo": { ...local device config... }}

This exact response occurs identically for:
- A deliberately wrong, plain alphanumeric test password
- The real, correct account password

Since the failure is identical regardless of what's typed, this is a
client-side bug in the password handling path (likely in the IPC hand-off
between the renderer's login form and the main process, or in whatever
routine is expected to encode/decode the password locally) that fails
*before* any credential is ever sent to your servers for verification. The
account itself is not the problem — the client simply never gets far enough
to check it. The UI also never surfaces this "Password decoding failed"
message to the user; it just hangs on "Connecting..." forever, which made
this very hard to diagnose without instrumenting the app directly.

Timeline
--------
- 2026-08-26 ~16:01 UTC: Desktop client's background session first starts
  failing a websocket reconnect with "Invalid close opcode" — recurring
  every 30-70s from this point forward. Earliest sign of trouble.
- 2026-08-26 ~23:50 UTC: A login attempt via the desktop GUI shows "Your
  account is cancelled. Contact your administrator." (Likely also a
  symptom of the same underlying client bug, not a real account state —
  see below.)
- 2026-08-27 ~17:01 UTC: VM rebooted; client auto-updated 1.3.0 -> 1.4.0 in
  the process. Same symptoms persisted post-update.
- 2026-08-27: Performed a clean uninstall (apt remove) and reinstall of the
  1.4.0 .deb client, preserving the existing local device-identity cache
  (device_id he9zabssi3wm3gids9btlrnci8a4qbkjvqbc5qoacuoo7jgets) so the
  reinstall would reattach to the existing device rather than creating a
  new enrollment. Same login failure persists on the fresh install.
- 2026-08-27: Used Chrome DevTools Protocol (--remote-debugging-port) to
  inspect the running client directly and captured the actual internal
  login response shown above, isolating the failure to client-side
  password decoding rather than network or account state.

What we've ruled out
---------------------
- Network/DNS/firewall: api.idrive360.com, wsn4.idrive360.com, and the
  account's assigned EVS server (evs5497.idrive.com, matching the
  SERVERADDRESS already cached locally) all resolve correctly; TCP/TLS
  connections succeed and respond as expected (confirmed via curl and raw
  socket tests, including a raw banner grab from the EVS server on port 443
  returning a valid "@IDEVSD" protocol response).
- Account/device state: the MSP API (device/summary) shows this device as
  status "online" with an intact, correctly-named backup plan attached, so
  the backend recognizes the device and account fine.
- Local config file "corruption": we initially suspected CONFIGURATION_FILE
  and related state files were corrupted (they looked like binary garbage
  under a naive base64 decode). That was a red herring on our end — we
  reverse-engineered the client's actual encode/decode scheme (base64, then
  the first quarter of the string swapped with the last quarter) from an
  older CLI-based client install we had on hand, and confirmed the current
  CONFIGURATION_FILE decodes to fully valid, correct JSON. No corruption is
  present.
- Wrong device enrollment: verified via MSP API and the local device
  identity cache (.device_id / .uuid_cache) before the reinstall's first
  launch; confirmed no new device folder was created.

Reproduction
------------
1. Launch idrive360-client 1.4.0.
2. On the login form, enter any password (tested with both a simple wrong
   password and the real correct one) and click Sign In.
3. UI shows "Connecting..." and never changes state.
4. Inspecting via CDP (Runtime.consoleAPICalled on the client's own
   "Login response received:" console.log call, then
   Runtime.callFunctionOn + JSON.stringify on the logged object) shows:
   LoginResp.message == "Password decoding failed" in both cases.

Request
-------
This looks like a genuine bug in the 1.4.0 Linux desktop client's login
handling, not an account or server-side issue. Could you:
1. Check whether there's a known issue with password decoding in 1.4.0 on
   Linux, and whether a fix or a rollback to a known-good build (we were
   previously on 1.3.0) is available?
2. Confirm the account itself (hoot-glowing24@icloud.com) has no actual
   restriction, in case the earlier "account is cancelled" message was more
   than a client-side artifact.

Happy to provide additional logs (trace logs, dashboard.log, CDP capture)
on request.
