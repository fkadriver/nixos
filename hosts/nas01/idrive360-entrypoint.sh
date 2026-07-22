#!/bin/bash
# IDrive360 container entrypoint.
# /opt/IDrive360 is a persistent volume (seeded from the pre-rebuild backup, so
# the device registration survives). /seed holds the installer .deb and the
# rescued /etc/idrive360cron binary. The container filesystem is ephemeral, so
# runtime deps and the cron binary are restored on every container recreation.
set -e
export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null 2>&1; then
    # Cache apt lists in the persistent volume so the 25 MB index isn't
    # re-downloaded on every container restart (ubuntu:24.04 is ephemeral).
    APT_CACHE=/opt/IDrive360/.apt-cache
    mkdir -p "$APT_CACHE/lists" "$APT_CACHE/debs"
    if ls "$APT_CACHE/lists/"*InRelease >/dev/null 2>&1; then
        cp -r "$APT_CACHE/lists/." /var/lib/apt/lists/
    else
        apt-get update
        cp -r /var/lib/apt/lists/. "$APT_CACHE/lists/" 2>/dev/null || true
    fi
    apt-get install -y --no-install-recommends \
        -o Dir::Cache::Archives="$APT_CACHE/debs" \
        libnss3 curl ca-certificates debianutils tar cron libnotify-bin \
        libexpat1 libpopt0 xvfb net-tools
fi

# The seeded profile is uid 1000 and the agent resolves user "scott" by name
# (fails with "Failed to save user configuration" otherwise); ubuntu:24.04
# ships uid 1000 as "ubuntu", so replace it
if ! id scott >/dev/null 2>&1; then
    userdel -r ubuntu 2>/dev/null || true
    useradd -u 1000 -m -s /bin/bash scott
fi

if [ ! -x /etc/idrive360cron ]; then
    if [ -f /seed/idrive360cron.bin ]; then
        # The binary refuses to run unless $0 is a symlink (vendor packaging
        # check: unless(-l $0){ saferetreat('you_cant_run_supporting_service') })
        install -m 755 /seed/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif ls /seed/IDrive360_*.deb >/dev/null 2>&1; then
        # Fresh bootstrap: postinst registers the device with the token embedded
        # in the .deb filename and downloads the backup engine into /opt/IDrive360
        dpkg -i /seed/IDrive360_*.deb
    else
        echo "ERROR: no idrive360cron binary and no installer .deb in /seed" >&2
        exit 1
    fi
fi

# The daemon's job schedule lives at /etc/idrive360crontab.json (ephemeral,
# recreated empty on container start); the app maintains a copy in the
# persistent volume — without it no jobs run and the console shows offline
if [ -s /opt/IDrive360/crontab.bak ] && [ ! -s /etc/idrive360crontab.json ]; then
    cp /opt/IDrive360/crontab.bak /etc/idrive360crontab.json
fi

# Electron CDP server requires a display; start a virtual framebuffer so
# cdp-client/server can connect and the Perl scripts can save config.
# Without this, every CDP attempt leaks a D-state process until OOM.
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &

exec /etc/idrive360cron --cron
