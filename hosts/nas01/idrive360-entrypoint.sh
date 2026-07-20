#!/bin/bash
# IDrive360 container entrypoint.
# /opt/IDrive360 is a persistent volume (seeded from the pre-rebuild backup, so
# the device registration survives). /seed holds the installer .deb and the
# rescued /etc/idrive360cron binary. The container filesystem is ephemeral, so
# runtime deps and the cron binary are restored on every container recreation.
set -e
export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends \
        libnss3 curl ca-certificates debianutils tar cron libnotify-bin \
        libexpat1 libpopt0
    rm -rf /var/lib/apt/lists/*
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

exec /etc/idrive360cron --cron
