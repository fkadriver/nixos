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
        libnss3 curl ca-certificates debianutils tar cron libnotify-bin
    rm -rf /var/lib/apt/lists/*
fi

if [ ! -x /etc/idrive360cron ]; then
    if [ -f /seed/idrive360cron.bin ]; then
        install -m 755 /seed/idrive360cron.bin /etc/idrive360cron
    elif ls /seed/IDrive360_*.deb >/dev/null 2>&1; then
        # Fresh bootstrap: postinst registers the device with the token embedded
        # in the .deb filename and downloads the backup engine into /opt/IDrive360
        dpkg -i /seed/IDrive360_*.deb
    else
        echo "ERROR: no idrive360cron binary and no installer .deb in /seed" >&2
        exit 1
    fi
fi

exec /etc/idrive360cron --cron
