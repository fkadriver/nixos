#!/usr/bin/env bash
# Provisioning script for sands-bak01 (HP ProDesk 600 G4 DM, 8GB RAM) - the
# IDrive360 backup agent's dedicated hardware host. See MIGRATION.md in the
# idrive360 repo for the full story of how this host came to be.
#
# sands-bak01 is deliberately NOT a NixOS host (IDrive360's Electron client
# needs a "normal" Ubuntu desktop stack - see MIGRATION.md's Phase 1 for why
# that was the call). So unlike every other machine in this repo, there's no
# flake target for it - this script is the only "declarative" record of its
# config, run by hand after a base OS install rather than during a
# nixos-rebuild.
#
# PREREQUISITE (do this first, outside this script): install plain
# Ubuntu Server 24.04 LTS (the "minimal"/"ubuntu-server-minimal" option in
# the installer) - partitioning (LVM, EFI boot), hostname (sands-bak01), and
# the `scott` user (with sudo) are all handled by the installer itself, not
# by this script. Boot it, SSH in, then run this script:
#   sudo bash setup.sh
#
# This script is meant to be idempotent - re-running it after a partial run
# should be safe, though it wasn't written to survive every possible failure
# mode (nas01-backup-setup.sh's cloud-init version is the more
# battle-tested sibling of a lot of this content).
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,23p' "$0" | sed 's/^# \?//'
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo bash setup.sh)." >&2
  exit 1
fi

SCOTT_HOME=/home/scott
# nas01's Tailscale IP, not hostname - avoids a DNS-not-ready-at-boot race
# for the NFS mounts below (see the fstab comment). Update if nas01's
# tailscale IP ever changes.
NAS01_TS_IP=100.73.114.76
# nas01's LAN IP - used only for the borg backup (see step 13 below), so
# that backup doesn't depend on Tailscale being up at all.
NAS01_LAN_IP=192.168.10.20
WAZUH_MANAGER_HOST=wazuh.warthog-royal.ts.net
WAZUH_AGENT_VERSION=4.14.5-1

echo "=== [1/15] Base packages ==="
apt-get update
apt-get install -y \
  software-properties-common apt-transport-https ca-certificates \
  nfs-common \
  lxde-core lightdm \
  wmctrl xdotool x11-utils scrot \
  borgbackup jq \
  smartmontools \
  net-tools \
  btop strace iperf3

echo "=== [2/15] Passwordless sudo for scott ==="
# This host isn't behind the nixos repo's narrowly-scoped
# security.sudo.extraRules (nixos-rebuild/nix/tailscale/borg only) - it gets
# full passwordless sudo instead, since it's single-user hardware with no
# other accounts and everything on it is remote-administered.
install -m 0440 /dev/stdin /etc/sudoers.d/scott-nopasswd <<'EOF'
scott ALL=(ALL) NOPASSWD: ALL
EOF
visudo -c -f /etc/sudoers.d/scott-nopasswd

echo "=== [3/15] Tailscale ==="
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y tailscale
fi
systemctl enable --now tailscaled

echo "=== [4/15] Fix tailscaled boot ordering ==="
# The stock unit only orders After=network-pre.target (fires very early,
# before eno1 has DHCP/a default route). Confirmed live (2026-09-25):
# tailscaled starting on a still-dead network hits "network is unreachable"
# on every DERP bootstrap-DNS lookup, and is left in a degraded state that
# only a manual `systemctl restart tailscaled` clears - NFS mounts to
# nas01 (and even SSH itself) failed for a full 10 minutes on a real
# reboot until this was noticed and fixed. network-online.target (backed
# by NetworkManager-wait-online.service, already enabled by default) is
# reached at the exact moment the link actually comes up - ordering
# tailscaled after it avoids the race instead of tailscaled having to
# recover from it.
mkdir -p /etc/systemd/system/tailscaled.service.d
cat > /etc/systemd/system/tailscaled.service.d/override.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target
EOF
systemctl daemon-reload
if ! tailscale status >/dev/null 2>&1; then
  echo "  Not logged in to Tailscale yet."
  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    tailscale up --ssh --authkey="$TAILSCALE_AUTHKEY"
  else
    echo "  Run this manually (an interactive login, or pass"
    echo "  TAILSCALE_AUTHKEY=... to this script - the shared key is the"
    echo "  Bitwarden 'NixOS Machines Auth Key' item used fleet-wide):"
    echo "    sudo tailscale up --ssh"
  fi
else
  echo "  Already logged in - skipping. (--ssh must still be set: run"
  echo "  'sudo tailscale up --ssh' by hand if this host predates it.)"
fi

echo "=== [5/15] xpra (remote GUI view, no VNC) ==="
if ! command -v xpra >/dev/null 2>&1; then
  curl -fsSL https://xpra.org/xpra.asc -o /usr/share/keyrings/xpra.asc
  cat > /etc/apt/sources.list.d/xpra.sources <<'EOF'
Types: deb
URIs: https://xpra.org
Suites: noble
Components: main
Signed-By: /usr/share/keyrings/xpra.asc
EOF
  apt-get update
  apt-get install -y xpra
fi
# The Debian xpra package's default 'start' command (/etc/X11/Xsession true)
# errors under this minimal env and throws a stray xmessage popup alongside
# the real IDrive360 window (confirmed live on the nas01-backup VM,
# 2026-08-29) - same fix applies here. Passing --start= on the command line
# does NOT override it (list-type config value), so it has to be disabled
# in the config file itself.
sed -i 's|^start = /etc/X11/Xsession true|#start = /etc/X11/Xsession true|' \
  /etc/xpra/conf.d/60_server.conf
# The unit is installed now but NOT enabled yet - it starts
# idrive360-client, which isn't installed until the manual step at the end
# of this script. Enable it once that's done:
#   sudo systemctl enable --now idrive360-xpra.service
cat > /etc/systemd/system/idrive360-xpra.service <<'EOF'
[Unit]
Description=Xpra seamless session for IDrive360 GUI (remote view without VNC)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=scott
Environment=HOME=/home/scott
# '+' prefix: runs as root regardless of the unit's User=, needed since
# this file is root-owned 0644.
ExecStartPre=+/usr/bin/sed -i 's|^start = /etc/X11/Xsession true|#start = /etc/X11/Xsession true|' /etc/xpra/conf.d/60_server.conf
ExecStart=/usr/bin/xpra start :100 --daemon=no --systemd-run=no --exit-with-children=yes --start-child="/opt/IDrive360/idrive360-client --user-data-dir=/home/scott/.config/idrive360-client-xpra" --socket-dir=/home/scott/.xpra --html=off --pulseaudio=no --notifications=no --mdns=no
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
# The dashboard/heartbeat subprocess (web console online status + logs -
# see MIGRATION.md's "ROOT CAUSE FOUND" and later sections) self-daemonizes:
# the process ExecStart launches double-forks and exits immediately, while
# the real long-lived process reparents to init and writes its own PID to
# idrive360.pid. Type=forking + PIDFile= (not Type=simple) is required -
# confirmed live (2026-09-25) that Type=simple sees the initial process
# exit (its normal, correct behavior) and restart-loops forever, since
# systemd is tracking the wrong process. The GUI never launches this on
# its own (still true as of 1.5.1 - confirmed live) hence a dedicated unit.
# Installed now but NOT enabled yet - same reason as idrive360-xpra.service
# above (needs idrive360-client installed first, manual step at the end):
#   sudo systemctl enable --now idrive360-dashboard.service
cat > /etc/systemd/system/idrive360-dashboard.service <<'EOF'
[Unit]
Description=IDrive360 dashboard/heartbeat (web console online status + logs)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=scott
WorkingDirectory=/opt/IDrive360
ExecStart=/opt/IDrive360/Idrivelib/dependencies/python/idrive360 start
PIDFile=/opt/IDrive360/idriveIt/user_profile/scott/idrive360.pid
Restart=on-failure
RestartSec=5
TimeoutStartSec=15

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

echo "=== [6/15] LightDM autologin (scott -> LXDE) ==="
install -d /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<'EOF'
[Seat:*]
autologin-user=scott
autologin-user-timeout=0
autologin-session=LXDE
EOF

echo "=== [7/15] Chromium sandbox fix (AppArmor unprivileged userns) ==="
# Ubuntu 24.04 hardening (kernel.apparmor_restrict_unprivileged_userns=1)
# blocks Electron/Chromium's sandbox from acquiring CAP_SYS_ADMIN, which
# breaks the IDrive360 client GUI. Confirmed this session.
cat > /etc/sysctl.d/99-idrive360-sandbox.conf <<'EOF'
kernel.apparmor_restrict_unprivileged_userns=0
EOF
sysctl --system >/dev/null

echo "=== [8/15] Disable all automatic updates ==="
# Deliberate: an automatic update broke the nas01-backup VM in the past
# (see MIGRATION.md in the idrive360 repo). This host is administered by
# hand (apt run manually) instead - masked, not just disabled, so nothing
# can silently re-enable these.
systemctl stop apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
  apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer \
  unattended-upgrades.service 2>/dev/null || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
  apt-daily-upgrade.service unattended-upgrades.service
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
if command -v snap >/dev/null 2>&1; then
  snap refresh --hold >/dev/null 2>&1 || true
fi
# Ubuntu Pro's livepatch applies kernel patches automatically (no reboot
# needed) - same "administered by hand" philosophy applies, and its snap's
# network-namespace mount (/run/snapd/ns/canonical-livepatch.mnt) was
# confirmed live (2026-09-25) to be the slowest thing in this host's
# shutdown sequence once the NFS mount timeouts (step 10) were fixed.
# Disabling the service alone isn't enough - the mount persists as long as
# the snap itself is installed, so remove it outright.
pro disable livepatch 2>/dev/null || true
snap remove canonical-livepatch 2>/dev/null || true

echo "=== [9/15] Timezone ==="
timedatectl set-timezone America/Chicago

echo "=== [10/15] NFS mounts to nas01 ==="
# /pool and /mnt: read-only, this host only ever reads source data for
# backup. ~/git/idrive360: read-write, it's a live shared checkout (this
# repo's twin - see idrive360-agent-status.sh below).
#
# x-systemd.automount (+ idle-timeout=0 so it stays mounted once triggered,
# not lazily unmounted): defense-in-depth, not the primary fix. The actual
# root cause of these mounts failing on boot was tailscaled itself
# starting before the network was ready (see step 4 above) - once that's
# fixed, an eager mount should just work. automount is kept anyway so a
# mount attempt never blocks boot waiting on Tailscale at all, whatever
# the reason.
#
# /pool and /mnt additionally get timeo=30,retrans=1 (NFS-level, ~3-6s
# worst case per RPC instead of the 60s/2-retry default) and a shorter
# x-systemd.mount-timeout=10s - confirmed live (2026-09-25) that shutdown
# hung for several minutes waiting on these to unmount cleanly. Safe to
# cut aggressively since both are read-only: nothing to flush, a timed-out
# unmount just means the next boot re-mounts cleanly. ~/git/idrive360 is
# read-write, so it keeps the more conservative NFS/systemd defaults
# (timeo=600,retrans=2 implicit, x-systemd.mount-timeout=30s).
mkdir -p /pool /mnt "$SCOTT_HOME/git/idrive360"
chown scott:scott "$SCOTT_HOME/git/idrive360"
for line in \
  "$NAS01_TS_IP:/pool    /pool    nfs    ro,_netdev,nofail,noatime,nconnect=8,timeo=30,retrans=1,x-systemd.automount,x-systemd.idle-timeout=0,x-systemd.mount-timeout=10s    0  0" \
  "$NAS01_TS_IP:/mnt     /mnt     nfs    ro,_netdev,nofail,noatime,nconnect=8,timeo=30,retrans=1,x-systemd.automount,x-systemd.idle-timeout=0,x-systemd.mount-timeout=10s    0  0" \
  "$NAS01_TS_IP:$SCOTT_HOME/git/idrive360    $SCOTT_HOME/git/idrive360    nfs    rw,_netdev,nofail,noatime,x-systemd.automount,x-systemd.idle-timeout=0,x-systemd.mount-timeout=30s    0  0"
do
  grep -qF "$line" /etc/fstab || echo "$line" >> /etc/fstab
done
systemctl daemon-reload
mount -a || echo "  (some mounts may need tailscale/nas01 reachable first - rerun 'mount -a' later)"

echo "=== [11/15] Starship prompt ==="
if ! command -v starship >/dev/null 2>&1; then
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi
su - scott -c 'grep -q "starship init bash" ~/.bashrc' || \
  su - scott -c 'printf "\n# Starship prompt\neval \"\$(starship init bash)\"\n" >> ~/.bashrc'

echo "=== [12/15] Fleet SSH aliases + idrive-status ==="
# Matches modules/shell-aliases.nix in this repo (kept in sync by hand,
# since this host can't import it directly).
su - scott -c 'grep -q "Fleet SSH shortcuts" ~/.bashrc' || su - scott -c "cat >> ~/.bashrc" <<'EOF'

# Fleet SSH shortcuts (matches modules/shell-aliases.nix in the nixos repo)
alias nas01='tailscale ssh nas01'
alias log01='tailscale ssh log01'
alias latitude='tailscale ssh latitude'
alias vm01='tailscale ssh vm01'
EOF
# idrive360-agent-status.sh is tracked in the idrive360 repo, NFS-shared
# above at ~/git/idrive360 - copy it in rather than re-embedding it here.
if [ -f "$SCOTT_HOME/git/idrive360/idrive360-agent-status.sh" ]; then
  install -m 0755 "$SCOTT_HOME/git/idrive360/idrive360-agent-status.sh" \
    /usr/local/bin/idrive360-agent-status.sh
  su - scott -c 'grep -q "alias idrive-status=" ~/.bashrc' || \
    su - scott -c "echo \"alias idrive-status='/usr/local/bin/idrive360-agent-status.sh'\" >> ~/.bashrc"
else
  echo "  ~/git/idrive360 not mounted yet - rerun this step once it is:"
  echo "    sudo install -m 0755 ~/git/idrive360/idrive360-agent-status.sh /usr/local/bin/"
fi

echo "=== [13/15] Borg backup of /opt/IDrive360 ==="
# IDrive360 doesn't back up its own install/identity directory - despite
# /opt/ being in its backup set, no backup log ever showed a [SUCCESS]
# entry under /opt/IDrive360/ itself. That directory holds the exact
# identity/cache files ("ROOT CAUSE FOUND" in MIGRATION.md) that took a
# full session to diagnose and restore, so it gets its own daily backup.
# Unencrypted (--encryption none) by deliberate choice - app files/cache,
# not personal data, and this host is outside the fleet's Bitwarden
# secrets management that the encrypted repos elsewhere rely on.
#
# Connects over the direct LAN, not Tailscale: confirmed live (2026-09-25)
# that a Tailscale outage took this backup down with it too. A dedicated
# key, restricted server-side to exactly `borg serve` on this repo path
# (no shell access - see the "manual steps" printed at the end), makes it
# independent of Tailscale entirely.
if [ ! -f "$SCOTT_HOME/.ssh/id_ed25519_borg_lan" ]; then
  su - scott -c "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_borg_lan -C sands-bak01-borg-lan"
fi
install -m 0755 /dev/stdin /usr/local/bin/borg-backup-idrive360.sh <<EOF
#!/bin/sh
# Daily borg backup of /opt/IDrive360 to nas01:/pool/borg/sands-bak01, over
# the direct LAN (see step 13's comment in setup.sh for why).
# borg exit codes: 0=success, 1=warning (e.g. a file vanishing mid-scan -
# expected, IDrive360 is actively writing under this path), 2+=real error.
# Run both steps regardless of a rc=1 warning; only abort/fail on rc>=2.
set -u

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_RSH="ssh -i $SCOTT_HOME/.ssh/id_ed25519_borg_lan -o StrictHostKeyChecking=accept-new"
REPO="ssh://scott@${NAS01_LAN_IP}/pool/borg/sands-bak01"

borg create --stats --show-rc --compression auto,zstd \\
  --exclude "*-wal" --exclude "*-shm" \\
  "\$REPO::{hostname}-{now:%Y-%m-%d_%H:%M:%S}" \\
  /opt/IDrive360
create_rc=\$?
[ "\$create_rc" -ge 2 ] && exit "\$create_rc"

borg prune --stats --show-rc \\
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 \\
  "\$REPO"
prune_rc=\$?
[ "\$prune_rc" -ge 2 ] && exit "\$prune_rc"

exit 0
EOF
cat > /etc/systemd/system/borg-backup-idrive360.service <<'EOF'
[Unit]
Description=Borg backup of /opt/IDrive360 to nas01:/pool/borg/sands-bak01
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=scott
ExecStart=/usr/local/bin/borg-backup-idrive360.sh
EOF
cat > /etc/systemd/system/borg-backup-idrive360.timer <<'EOF'
[Unit]
Description=Daily borg backup of /opt/IDrive360

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
# Repo must exist before the first run, and nas01 must already trust this
# host's borg-LAN key (manual step, printed at the end) - safe to re-run
# either way (borg init on an already-initialized repo just errors
# harmlessly, ignored here; the timer will just fail until the key's added).
su - scott -c "BORG_RELOCATED_REPO_ACCESS_IS_OK=yes BORG_RSH='ssh -i $SCOTT_HOME/.ssh/id_ed25519_borg_lan -o StrictHostKeyChecking=accept-new' borg init --encryption none ssh://scott@${NAS01_LAN_IP}/pool/borg/sands-bak01" 2>/dev/null || true
systemctl enable --now borg-backup-idrive360.timer

echo "=== [14/15] Wazuh agent ==="
if ! dpkg -l wazuh-agent >/dev/null 2>&1; then
  curl -sS -o /tmp/wazuh-agent.deb \
    "https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_${WAZUH_AGENT_VERSION}_amd64.deb"
  WAZUH_MANAGER="$WAZUH_MANAGER_HOST" dpkg -i /tmp/wazuh-agent.deb
fi
# Wazuh visibility for IDrive360's backup status (read-only, never touches
# the IDrive360 install itself). A command wrapper that reads the status
# file fresh every run, not a <localfile> tail - Wazuh's logcollector does
# NOT reliably detect these files being rewritten in place (confirmed live
# 2026-07-28 on the nas01-backup VM). See docs/idrive360.md in this repo.
install -m 0755 /dev/stdin /usr/local/bin/wazuh-idrive360-status <<'STATUSEOF'
#!/usr/bin/env bash
set -euo pipefail

# Converts a "<number><unit>" string (B, KB, MB, GB, TB; case-insensitive,
# no space) to a plain MB float. Echoes "unknown" if it doesn't parse.
to_mb() {
    local raw="$1" num unit
    num=$(grep -oP '^[0-9.]+' <<<"$raw") || true
    unit=$(grep -oP '[A-Za-z]+$' <<<"$raw" | tr '[:lower:]' '[:upper:]') || true
    if [ -z "$num" ] || [ -z "$unit" ]; then
        echo "unknown"
        return
    fi
    case "$unit" in
        B)  awk -v n="$num" 'BEGIN{printf "%.4f", n/1048576}' ;;
        KB) awk -v n="$num" 'BEGIN{printf "%.4f", n/1024}' ;;
        MB) awk -v n="$num" 'BEGIN{printf "%.4f", n}' ;;
        GB) awk -v n="$num" 'BEGIN{printf "%.4f", n*1024}' ;;
        TB) awk -v n="$num" 'BEGIN{printf "%.4f", n*1024*1024}' ;;
        *)  echo "unknown" ;;
    esac
}

STATUS_FILE=$(ls /opt/IDrive360/idriveIt/user_profile/scott/*/.userInfo/lastOnlineBackupStatus.json 2>/dev/null | head -1) || true

if [ -z "$STATUS_FILE" ] || [ ! -f "$STATUS_FILE" ]; then
    echo "idrive360_backup: status=UNKNOWN error=status_file_not_found"
    exit 0
fi

STATUS=$(grep -oP '"status"\s*:\s*"\K[^"]+' "$STATUS_FILE" 2>/dev/null || echo "")
TIME=$(grep -oP '"time"\s*:\s*\K[0-9]+' "$STATUS_FILE" 2>/dev/null || echo "0")

if [ -z "$STATUS" ]; then
    echo "idrive360_backup: status=UNKNOWN error=status_field_missing"
    exit 0
fi

# Report what was actually transferred in the most recent run (Scheduled/Manual
# full backup or hourly CDP sync, whichever is newer) regardless of the status
# field above -- that field is unreliable due to a vendor pid.txt bug that
# misreports Failure even when the transfer itself succeeded (docs/idrive360.md).
LATEST_LOG=$(ls -t /opt/IDrive360/idriveIt/user_profile/scott/*/Backup/DefaultBackupSet/LOGS/* /opt/IDrive360/idriveIt/user_profile/scott/*/CDP/DefaultBackupSet/LOGS/* 2>/dev/null | head -1) || true

FILES_BACKED_UP="unknown"
SIZE_BACKED_UP="unknown"
SIZE_BACKED_UP_MB="unknown"
FILES_FAILED="unknown"
LOG_NAME="none"

if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
    LOG_NAME=$(basename "$LATEST_LOG")
    PARSED=$(grep -oP '[Bb]acked up now\s*:?\s*\K[0-9]+' "$LATEST_LOG" | head -1) || true
    if [ -n "$PARSED" ]; then FILES_BACKED_UP="$PARSED"; fi
    PARSED=$(grep -oP 'Size of backed up files:\s*\K[0-9.]+\s*[A-Za-z]+' "$LATEST_LOG" | head -1) || true
    if [ -n "$PARSED" ]; then
        SIZE_BACKED_UP="${PARSED// /}"
        SIZE_BACKED_UP_MB=$(to_mb "$SIZE_BACKED_UP")
    fi
    PARSED=$(grep -oP '[Ff]ailed to backup\s*:?\s*\K[0-9]+' "$LATEST_LOG" | head -1) || true
    if [ -n "$PARSED" ]; then FILES_FAILED="$PARSED"; fi
fi

echo "idrive360_backup: status=${STATUS} time=${TIME} files_backed_up=${FILES_BACKED_UP} size_backed_up=${SIZE_BACKED_UP} size_backed_up_mb=${SIZE_BACKED_UP_MB} files_failed=${FILES_FAILED} log=${LOG_NAME}"
STATUSEOF

install -m 0755 /dev/stdin /usr/local/bin/idrive360-wazuh-command.py <<'PYEOF'
#!/usr/bin/env python3
conf_path = "/var/ossec/etc/ossec.conf"
with open(conf_path) as f:
    content = f.read()

marker = "idrive360-command-localfile"
if marker in content:
    print("already present, skipping")
    raise SystemExit(0)

block = """  <!-- %s: reads IDrive360's status file fresh on every run
       (see /usr/local/bin/wazuh-idrive360-status). -->
    <localfile>
      <log_format>command</log_format>
      <command>/usr/local/bin/wazuh-idrive360-status</command>
      <alias>idrive360 backup status</alias>
      <frequency>900</frequency>
    </localfile>

</ossec_config>
""" % marker

idx = content.rfind("</ossec_config>")
with open(conf_path, "w") as f:
    f.write(content[:idx] + block)
print("patched")
PYEOF
python3 /usr/local/bin/idrive360-wazuh-command.py

# Infra health check (mounts, Tailscale/nas01 reachability, key services) -
# same command-wrapper pattern as the status check above, for the same
# reason (a stale NFS mount or a degraded tailscaled won't show up in a
# simple file tail). See MIGRATION.md's reboot-reliability section for the
# incident this exists to catch.
install -m 0755 /dev/stdin /usr/local/bin/wazuh-sands-bak01-health <<'HEALTHEOF'
#!/usr/bin/env bash
set -uo pipefail

NAS01_TS_IP=100.73.114.76

if systemctl is-active --quiet tailscaled; then TS_SVC=up; else TS_SVC=down; fi

if timeout 5 bash -c "echo > /dev/tcp/${NAS01_TS_IP}/22" 2>/dev/null; then
  NAS01_TCP=reachable
else
  NAS01_TCP=unreachable
fi

check_mount() {
  timeout 5 stat "$1" >/dev/null 2>&1 && echo ok || echo unresponsive
}
POOL_MOUNT=$(check_mount /pool)
MNT_MOUNT=$(check_mount /mnt)
IDRIVE_REPO_MOUNT=$(check_mount /home/scott/git/idrive360)

if systemctl is-active --quiet idrive360cron; then IDRIVE_SVC=up; else IDRIVE_SVC=down; fi
if systemctl is-active --quiet borg-backup-idrive360.timer; then BORG_TIMER=up; else BORG_TIMER=down; fi

FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null | wc -l)

echo "sands_bak01_health: tailscaled=${TS_SVC} nas01_tcp22=${NAS01_TCP} pool_mount=${POOL_MOUNT} mnt_mount=${MNT_MOUNT} idrive360_repo_mount=${IDRIVE_REPO_MOUNT} idrive360cron=${IDRIVE_SVC} borg_timer=${BORG_TIMER} failed_units=${FAILED_UNITS}"
HEALTHEOF

install -m 0755 /dev/stdin /usr/local/bin/wazuh-health-command.py <<'PYEOF2'
#!/usr/bin/env python3
conf_path = "/var/ossec/etc/ossec.conf"
with open(conf_path) as f:
    content = f.read()

marker = "sands-bak01-health-localfile"
if marker in content:
    print("already present, skipping")
    raise SystemExit(0)

block = """  <!-- %s: infra health check (mounts, Tailscale, key services) -
       see /usr/local/bin/wazuh-sands-bak01-health. -->
    <localfile>
      <log_format>command</log_format>
      <command>/usr/local/bin/wazuh-sands-bak01-health</command>
      <alias>sands-bak01 infra health</alias>
      <frequency>300</frequency>
    </localfile>

</ossec_config>
""" % marker

idx = content.rfind("</ossec_config>")
with open(conf_path, "w") as f:
    f.write(content[:idx] + block)
print("patched")
PYEOF2
python3 /usr/local/bin/wazuh-health-command.py

# Borg backup staleness for /opt/IDrive360 - same command-wrapper pattern,
# mirroring modules/borg-backup.nix's wazuh-borg-status used by the rest of
# the fleet. nas01's own fleet-wide borg-status.service also logs this
# repo's staleness, but that's attributed to nas01's agent, not
# sands-bak01's - this is the sands-bak01-native equivalent (confirmed live
# 2026-09-29 this was the actual gap: nothing borg-related showed up under
# sands-bak01's own agent in Wazuh without it). Needs jq (step 1) and the
# borg-LAN key (step 13, already run by this point).
install -m 0755 /dev/stdin /usr/local/bin/wazuh-borg-status <<'BORGEOF'
#!/usr/bin/env bash
# BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK is needed because wazuh runs
# this as root, which has never accessed this repo before (only scott has)
# - borg treats that as an unknown repo and refuses without it. Confirmed
# live 2026-09-29. That confirmation prompt prints to stderr regardless,
# so stdout/stderr must stay separated (a `2>&1` merge on the happy path
# corrupts the parsed borg list output with the warning text - also
# confirmed live) - stderr only gets read back in on an actual failure.
set -euo pipefail

REPO="ssh://scott@192.168.10.20/pool/borg/sands-bak01"
STALE_HOURS=25
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RSH="ssh -i /home/scott/.ssh/id_ed25519_borg_lan -o StrictHostKeyChecking=accept-new"

if ! command -v borg &>/dev/null; then
    echo "borg_backup: status=ERROR repo=${REPO} error=borg_not_found"
    exit 0
fi

ERRFILE=$(mktemp)
trap "rm -f \"\$ERRFILE\"" EXIT

LAST=$(borg list --last 1 --format '{archive}|{start:%Y-%m-%dT%H:%M:%S}' "$REPO" 2>"$ERRFILE") || {
    ERR=$(head -1 "$ERRFILE" 2>/dev/null | tr -cs '[:alnum:]_.-' '_' | cut -c1-60)
    echo "borg_backup: status=ERROR repo=${REPO} error=${ERR}"
    exit 0
}

if [ -z "$LAST" ]; then
    echo "borg_backup: status=EMPTY repo=${REPO} error=no_archives"
    exit 0
fi

ARCHIVE=$(printf '%s' "$LAST" | cut -d'|' -f1)
START=$(printf '%s' "$LAST" | cut -d'|' -f2)

START_EPOCH=$(date -d "${START/T/ }" +%s 2>/dev/null) || START_EPOCH=0
AGE_H=$(( ($(date +%s) - START_EPOCH) / 3600 ))

INFO_JSON=$(borg info --json "${REPO}::${ARCHIVE}" 2>/dev/null) || INFO_JSON=""

DURATION="0"
ORIGINAL_SIZE="unknown"
COMPRESSED_SIZE="unknown"
DEDUPLICATED_SIZE="unknown"
if [ -n "$INFO_JSON" ]; then
    DURATION=$(jq -r '.archives[0].duration // 0 | floor' <<<"$INFO_JSON" 2>/dev/null || echo "0")
    ORIGINAL_SIZE=$(jq -r '.archives[0].stats.original_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
    COMPRESSED_SIZE=$(jq -r '.archives[0].stats.compressed_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
    DEDUPLICATED_SIZE=$(jq -r '.archives[0].stats.deduplicated_size // "unknown"' <<<"$INFO_JSON" 2>/dev/null || echo "unknown")
fi

if [[ "$ARCHIVE" == *.failed ]]; then
    echo "borg_backup: status=ERROR repo=${REPO} archive=${ARCHIVE} start=${START} duration=${DURATION}s age=${AGE_H}h original_size=${ORIGINAL_SIZE} compressed_size=${COMPRESSED_SIZE} deduplicated_size=${DEDUPLICATED_SIZE} error=archive_marked_failed"
    exit 0
fi

if [ "$AGE_H" -gt "$STALE_HOURS" ]; then
    STATUS=STALE
else
    STATUS=OK
fi

echo "borg_backup: status=${STATUS} repo=${REPO} archive=${ARCHIVE} start=${START} duration=${DURATION}s age=${AGE_H}h original_size=${ORIGINAL_SIZE} compressed_size=${COMPRESSED_SIZE} deduplicated_size=${DEDUPLICATED_SIZE}"
BORGEOF

install -m 0755 /dev/stdin /usr/local/bin/wazuh-borg-status-command.py <<'PYEOF3'
#!/usr/bin/env python3
conf_path = "/var/ossec/etc/ossec.conf"
with open(conf_path) as f:
    content = f.read()

marker = "sands-bak01-borg-status-localfile"
if marker in content:
    print("already present, skipping")
    raise SystemExit(0)

block = """  <!-- %s: borg backup staleness for /opt/IDrive360 -
       see /usr/local/bin/wazuh-borg-status. -->
    <localfile>
      <log_format>command</log_format>
      <command>/usr/local/bin/wazuh-borg-status</command>
      <alias>sands-bak01 borg backup status</alias>
      <frequency>3600</frequency>
    </localfile>

</ossec_config>
""" % marker

idx = content.rfind("</ossec_config>")
with open(conf_path, "w") as f:
    f.write(content[:idx] + block)
print("patched")
PYEOF3
python3 /usr/local/bin/wazuh-borg-status-command.py

# Allow command/full_command entries the manager pushes via shared
# agent.conf - default is disabled for security. Without this,
# logcollector logs "Remote commands are not accepted from the manager"
# and silently drops them.
grep -q "remote_commands" /var/ossec/etc/local_internal_options.conf || \
  printf '%s\n' "logcollector.remote_commands=1" "wazuh_command.remote_commands=1" \
    >> /var/ossec/etc/local_internal_options.conf

# SMART drive health for Wazuh (gap found and closed 2026-09-29 - see
# MIGRATION.md). Two mechanisms, mirroring the fleet-wide pattern in the
# nixos repo's modules/smart-monitor.nix, adapted for a non-NixOS host:
#
# 1. Real-time alert: Debian/Ubuntu's smartd ships with -M exec pointed at
#    /usr/share/smartmontools/smartd-runner, which fans out to any
#    executable dropped in /etc/smartmontools/run.d/ (same mechanism the
#    stock 10mail script uses) - no smartd.conf edit needed beyond adding
#    -a so smartd actually monitors full attribute tables, not just health
#    status. Confirmed live via `smartd -q onecheck` with a temporary
#    `-M test` directive.
# 2. Periodic poll: wazuh-smart-status (synced copy of
#    modules/smart-monitor-smart-status.sh / wazuh-tailscale's
#    config/wazuh_cluster/scripts/smart-status.sh) deployed to
#    /var/ossec/scripts/ and invoked hourly by the manager once this host's
#    agent is assigned to the "smart-monitor" group (manual step below -
#    can't be scripted from this host, same as the borg-LAN key trust).
sed -i 's|^DEVICESCAN -d removable|DEVICESCAN -a -d removable|' /etc/smartd.conf

install -m 0755 /dev/stdin /etc/smartmontools/run.d/20wazuh-smart-alert <<'SMARTDALERTEOF'
#!/usr/bin/env bash
LOG=/var/log/smartd-alerts.log
echo "$(date '+%b %d %H:%M:%S') $(hostname) smartd: ALERT device=${SMARTD_DEVICE:-unknown} type=${SMARTD_FAILTYPE:-unknown} msg=${SMARTD_MESSAGE:-}" >> "$LOG"
SMARTDALERTEOF
touch /var/log/smartd-alerts.log
chmod 644 /var/log/smartd-alerts.log
systemctl restart smartmontools

mkdir -p /var/ossec/scripts
chown root:wazuh /var/ossec/scripts
chmod 750 /var/ossec/scripts
install -o root -g wazuh -m 0750 /dev/stdin /var/ossec/scripts/wazuh-smart-status <<'SMARTSTATUSEOF'
#!/usr/bin/env bash
# Fleet-wide SMART health poller - synced copy from wazuh-tailscale's
# config/wazuh_cluster/scripts/smart-status.sh / nixos's
# modules/smart-monitor-smart-status.sh, deployed here manually since
# sands-bak01 is plain Ubuntu, not NixOS (see MIGRATION.md). Invoked by the
# Wazuh manager as a command localfile via the "smart-monitor" agent group.
#
# Emits one 'smart_device: ...' line per physical drive from `smartctl
# --json`. Unifies ATA and NVMe into one schema:
#   - health:        smart_status.passed
#   - reallocated:   ATA attribute 5 (Reallocated_Sector_Ct) raw value, else 0
#   - pending:       ATA attribute 197 (Current_Pending_Sector) raw value, else 0
#   - media_errors:  NVMe nvme_smart_health_information_log.media_errors, else 0
#   - temp_c:        temperature.current, else 0
#
# Per-drive smartctl calls run in parallel - a fleet host with more drives
# hit Wazuh command-localfile's ~5s execution timeout running sequentially.
#
# Requires: smartctl (smartmontools), jq. Must run as root.
set -uo pipefail

poll_device() {
  local path="$1"
  local json passed health reallocated pending media_errors temp_c

  json=$(smartctl -H -A --json=c "$path" 2>/dev/null)
  passed=$(echo "$json" | jq -r '.smart_status.passed // empty' 2>/dev/null)
  if [ -z "$passed" ]; then
    return
  fi

  health="FAILED"
  [ "$passed" = "true" ] && health="PASSED"

  reallocated=$(echo "$json" | jq -r '[.ata_smart_attributes.table[]? | select(.id == 5) | .raw.value] | first // 0')
  pending=$(echo "$json" | jq -r '[.ata_smart_attributes.table[]? | select(.id == 197) | .raw.value] | first // 0')
  media_errors=$(echo "$json" | jq -r '.nvme_smart_health_information_log.media_errors // 0')
  temp_c=$(echo "$json" | jq -r '.temperature.current // 0')

  echo "smart_device: device=${path} health=${health} reallocated=${reallocated} pending=${pending} media_errors=${media_errors} temp_c=${temp_c}"
}

for dev in $(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" {print $1}'); do
  poll_device "/dev/${dev}" &
done
wait
SMARTSTATUSEOF

install -m 0755 /dev/stdin /usr/local/bin/wazuh-smart-alerts-command.py <<'PYEOF4'
#!/usr/bin/env python3
conf_path = "/var/ossec/etc/ossec.conf"
with open(conf_path) as f:
    content = f.read()

marker = "sands-bak01-smartd-alerts-localfile"
if marker in content:
    print("already present, skipping")
    raise SystemExit(0)

block = """  <!-- %s: real-time SMART failure/attribute-change alerts from smartd
       (fed via /etc/smartmontools/run.d/20wazuh-smart-alert). Periodic
       SMART poll is separate - via the smart-monitor Wazuh agent group,
       see /var/ossec/scripts/wazuh-smart-status. -->
    <localfile>
      <log_format>syslog</log_format>
      <location>/var/log/smartd-alerts.log</location>
    </localfile>

</ossec_config>
""" % marker

idx = content.rfind("</ossec_config>")
with open(conf_path, "w") as f:
    f.write(content[:idx] + block)
print("patched")
PYEOF4
python3 /usr/local/bin/wazuh-smart-alerts-command.py

# Fleet-wide disk usage poller (gap found and closed 2026-09-29 - see
# MIGRATION.md). Unlike SMART/ZFS, this needs no agent group assignment -
# it's already wired into the manager's shared/default/agent.conf, which
# every agent gets automatically. The command localfile was registered on
# this host from first enrollment (part of the "default" group everyone
# joins), but silently failed every 30 minutes ("command not found") until
# the script itself was deployed here - Wazuh's command-localfile execution
# doesn't surface that failure anywhere visible on the dashboard, so it went
# unnoticed until a manual check. Synced copy of
# modules/disk-usage-monitor-disk-usage-status.sh / wazuh-tailscale's
# config/wazuh_cluster/scripts/disk-usage-status.sh - same convention as
# wazuh-smart-status above, no ossec.conf edit needed here.
mkdir -p /var/ossec/scripts
chown root:wazuh /var/ossec/scripts
chmod 750 /var/ossec/scripts
install -o root -g wazuh -m 0750 /dev/stdin /var/ossec/scripts/wazuh-disk-usage-status <<'DISKUSAGEEOF'
#!/usr/bin/env bash
# Fleet-wide disk usage poller - synced copy from wazuh-tailscale's
# config/wazuh_cluster/scripts/disk-usage-status.sh / nixos's
# modules/disk-usage-monitor-disk-usage-status.sh, deployed here manually
# since sands-bak01 is plain Ubuntu, not NixOS (see MIGRATION.md). Invoked
# fleet-wide via the "default" Wazuh agent group (shared/default/agent.conf)
# - no group assignment needed, unlike SMART/ZFS.
#
# Emits two kinds of structured line:
#   disk_usage:        one per real filesystem (per-mount detail)
#   disk_usage_total:  one per host (single "how full is this machine" figure)
#
# status (ok/warning/critical) is computed here, not in Wazuh rules.
# Pseudo/virtual filesystems are excluded - not meaningful "disk usage".
#
# Requires GNU coreutils df (-T, -B1).
set -uo pipefail

WARN_PCT=85
CRIT_PCT=95

status_for_pcent() {
  local pcent="$1"
  if [ "$pcent" -ge "$CRIT_PCT" ]; then
    echo critical
  elif [ "$pcent" -ge "$WARN_PCT" ]; then
    echo warning
  else
    echo ok
  fi
}

EXCLUDE_TYPES='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup|cgroup2|nsfs|devpts|mqueue|hugetlbfs|efivarfs|debugfs|tracefs|configfs|binfmt_misc|autofs|rpc_pipefs|ramfs)$'

df -PT -B1 2>/dev/null | tail -n +2 | while read -r device fstype size used avail pcent mount; do
  [[ "$fstype" =~ $EXCLUDE_TYPES ]] && continue

  pcent_num="${pcent%\%}"
  status=$(status_for_pcent "$pcent_num")

  mount_safe=$(echo "$mount" | tr ' ' '_')
  echo "disk_usage: mount=${mount_safe} device=${device} fstype=${fstype} size_bytes=${size} used_bytes=${used} avail_bytes=${avail} pcent_used=${pcent_num} status=${status}"
done

read -r local_used_kb local_size_kb local_avail_kb <<<"$(df -kP -l 2>/dev/null | awk 'NR>1 && $1 ~ /^\/dev\//{u+=$3;s+=$2;a+=$4} END{print u+0, s+0, a+0}')"

zfs_used_kb=0
zfs_size_kb=0
zfs_avail_kb=0
if command -v zpool >/dev/null 2>&1 && [ -n "$(zpool list -H 2>/dev/null)" ]; then
  read -r zfs_used_kb zfs_size_kb zfs_avail_kb <<<"$(zpool list -Hp -o alloc,size,free 2>/dev/null | awk '{u+=$1;s+=$2;a+=$3} END{printf "%d %d %d\n", u/1024, s/1024, a/1024}')"
fi

total_used_kb=$(( ${local_used_kb:-0} + ${zfs_used_kb:-0} ))
total_size_kb=$(( ${local_size_kb:-0} + ${zfs_size_kb:-0} ))
total_avail_kb=$(( ${local_avail_kb:-0} + ${zfs_avail_kb:-0} ))

if [ "$total_size_kb" -gt 0 ]; then
  total_pcent=$(( total_used_kb * 100 / total_size_kb ))
  total_status=$(status_for_pcent "$total_pcent")
  echo "disk_usage_total: size_bytes=$((total_size_kb * 1024)) used_bytes=$((total_used_kb * 1024)) avail_bytes=$((total_avail_kb * 1024)) pcent_used=${total_pcent} status=${total_status}"
fi
DISKUSAGEEOF

echo "=== [15/15] Tailscale self-heal timer ==="
# This host is headless/unattended by design (set-it-and-forget-it) - the
# tailscaled boot-ordering fix (step 4) addresses the one root cause found
# so far, but this catches any *other* reason tailscale ever goes stale,
# automatically, instead of waiting for someone to notice. Checks real TCP
# reachability to nas01, not `tailscale ping` - confirmed live (2026-09-25)
# that a WireGuard-level ping can succeed while TCP is still broken.
#
# Also clears stale "failed" mount-unit states: confirmed live that an
# automount attempt can hit "access denied by server" on its very first
# try at boot, then succeed cleanly on the next access - the mount itself
# recovers on its own, but systemd leaves the unit marked failed, which
# then shows up as a false alarm in the Wazuh health check. Only clears
# it if the path is actually responsive right now; a genuinely broken
# mount stays reported as failed.
install -m 0755 /dev/stdin /usr/local/bin/tailscale-selfheal.sh <<'SELFHEALEOF'
#!/usr/bin/env bash
set -u

NAS01_TS_IP=100.73.114.76

if timeout 5 bash -c "echo > /dev/tcp/${NAS01_TS_IP}/22" 2>/dev/null; then
  :
else
  logger -t tailscale-selfheal "nas01 unreachable over tailscale (TCP/22) - restarting tailscaled"
  systemctl restart tailscaled
  sleep 10
  if timeout 5 bash -c "echo > /dev/tcp/${NAS01_TS_IP}/22" 2>/dev/null; then
    logger -t tailscale-selfheal "recovered after tailscaled restart"
  else
    logger -t tailscale-selfheal "still unreachable after tailscaled restart - needs attention"
  fi
fi

declare -A MOUNT_PATHS=(
  [pool.mount]=/pool
  [mnt.mount]=/mnt
  ["home-scott-git-idrive360.mount"]=/home/scott/git/idrive360
)
for unit in "${!MOUNT_PATHS[@]}"; do
  path="${MOUNT_PATHS[$unit]}"
  if systemctl is-failed --quiet "$unit"; then
    if timeout 5 stat "$path" >/dev/null 2>&1; then
      systemctl reset-failed "$unit"
      logger -t tailscale-selfheal "cleared stale failed state on $unit ($path is responsive)"
    else
      logger -t tailscale-selfheal "$unit is failed AND $path is unresponsive - needs attention"
    fi
  fi
done
SELFHEALEOF
cat > /etc/systemd/system/tailscale-selfheal.service <<'EOF'
[Unit]
Description=Check Tailscale reachability to nas01, restart tailscaled if broken
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tailscale-selfheal.sh
EOF
cat > /etc/systemd/system/tailscale-selfheal.timer <<'EOF'
[Unit]
Description=Periodic Tailscale reachability check

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now tailscale-selfheal.timer

echo ""
echo "=== Automated steps done. Manual steps remaining: ==="
echo ""
echo "1. IDrive360 client (no stable download URL - signed link expires,"
echo "   can't be scripted):"
echo "     a. Get the DEB download link from the IDrive360 web console"
echo "     b. wget -P ~ '<DEB-URL>'"
echo "     c. sudo apt install -y ~/IDrive360_*.deb"
echo "     d. The installer drops ~/.config/autostart/idrive360client.desktop"
echo "        which launches its own GUI --hidden on login. Set it to NOT"
echo "        launch there - idrive360-xpra.service (already installed above,"
echo "        just not yet enabled) must be the ONLY thing that ever starts"
echo "        idrive360-client, since Electron's single-instance lock means a"
echo "        second launch just signals the first and exits (confirmed live"
echo "        2026-08-29):"
echo "          sed -i 's/^Hidden=false/Hidden=true/' ~/.config/autostart/idrive360client.desktop"
echo "          sudo systemctl enable --now idrive360-xpra.service"
echo "          sudo systemctl enable --now idrive360-dashboard.service"
echo "        Then view it from a daily driver: idrive-app"
echo ""
echo "2. Wazuh enrollment (needs a real secret, can't be scripted - password:"
echo "   bw get item 'Wazuh Agent Enrollment', same secret every other host"
echo "   uses):"
echo "     sudo /var/ossec/bin/agent-auth -m $WAZUH_MANAGER_HOST -P '<password>' -A sands-bak01"
echo "     sudo systemctl enable --now wazuh-agent"
echo ""
echo "3. If Tailscale wasn't already logged in above: sudo tailscale up --ssh"
echo ""
echo "4. Trust this host's borg-LAN key on nas01 (needs a nixos repo commit +"
echo "   nixos-rebuild on nas01, can't be scripted from here - add the key"
echo "   below to users.users.scott.openssh.authorizedKeys.keys in"
echo "   hosts/nas01/default.nix, restricted per the existing example there):"
cat /home/scott/.ssh/id_ed25519_borg_lan.pub 2>/dev/null | sed 's/^/     /' || echo "     (run after this script: cat ~/.ssh/id_ed25519_borg_lan.pub)"
echo "   Until that's done, borg-backup-idrive360.timer will fail every run -"
echo "   check with: sudo systemctl status borg-backup-idrive360.service"
echo ""
echo "5. Assign this host's agent to the \"smart-monitor\" Wazuh group (needs"
echo "   the manager, can't be scripted from here - on log01, wazuh-tailscale"
echo "   repo, after step 2's enrollment above has registered the agent):"
echo "     docker compose exec wazuh.manager /var/ossec/bin/manage_agents -l"
echo "     docker compose exec wazuh.manager /var/ossec/bin/agent_groups -a -i <ID> -g smart-monitor -q"
echo "   Until that's done, the hourly wazuh-smart-status poll won't run -"
echo "   real-time smartd alerts (rule 100818) work regardless, no group"
echo "   assignment needed for those."
