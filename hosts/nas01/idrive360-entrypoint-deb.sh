#!/bin/bash
# IDrive360 container entrypoint (Ubuntu 24.04 / DEB variant).
# /opt/IDrive360 is a persistent volume; /seed holds the installer .deb and
# the rescued idrive360cron binary.  Container filesystem is ephemeral, so
# runtime deps and the cron binary are restored on every restart.
#
# First-boot flow (fresh registration):
#   1. Place IDrive360_<token>.deb in /seed (no idrive360cron.bin)
#   2. dpkg -i registers the device and downloads the engine into /opt/IDrive360
#   3. Entrypoint rescues the cron binary to /opt/IDrive360/idrive360cron.bin
#   4. All subsequent restarts use the rescued binary — no re-registration
set -e
export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null 2>&1 || ! dpkg -s libdbus-1-3 >/dev/null 2>&1; then
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
        libexpat1 libpopt0 xvfb net-tools \
        libdbus-1-3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 \
        libgtk-3-0t64 libpango-1.0-0 libcairo2 libxcomposite1 libxdamage1 \
        libxfixes3 libxkbcommon0 libasound2t64 libatspi2.0-0t64
fi

# The seeded profile is uid 1000 and the agent resolves user "scott" by name
# (fails with "Failed to save user configuration" otherwise); ubuntu:24.04
# ships uid 1000 as "ubuntu", so replace it
if ! id scott >/dev/null 2>&1; then
    userdel -r ubuntu 2>/dev/null || true
    useradd -u 1000 -m -s /bin/bash scott
fi

if [ ! -x /etc/idrive360cron ]; then
    # The binary refuses to run unless $0 is a symlink (vendor packaging check:
    # unless(-l $0){ saferetreat('you_cant_run_supporting_service') })
    if [ -f /opt/IDrive360/idrive360cron.bin ]; then
        # Fast path: binary was rescued here after the first dpkg install
        install -m 755 /opt/IDrive360/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif [ -f /seed/idrive360cron.bin ]; then
        # Legacy path: binary was placed directly in seed
        install -m 755 /seed/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif ls /seed/IDrive360_*.deb >/dev/null 2>&1; then
        # Fresh bootstrap: postinst registers the device with the token embedded
        # in the .deb filename and downloads the backup engine into /opt/IDrive360.
        # Set SUDO_USER so the vendor installer picks scott instead of falling
        # back to root (which would create user_profile/root instead of /scott).
        SUDO_USER=scott dpkg -i /seed/IDrive360_*.deb
        if [ -x /etc/idrive360cron ]; then
            REAL_BIN=$(readlink -f /etc/idrive360cron 2>/dev/null || echo /etc/idrive360cron)
            install -m 755 "$REAL_BIN" /opt/IDrive360/idrive360cron.bin
        fi
    else
        echo "ERROR: no idrive360cron binary and no installer .deb in /seed" >&2
        exit 1
    fi
fi

if [ -s /opt/IDrive360/crontab.bak ] && [ ! -s /etc/idrive360crontab.json ]; then
    cp /opt/IDrive360/crontab.bak /etc/idrive360crontab.json
fi
touch /etc/idrive360crontab.json
chown scott:scott /etc/idrive360crontab.json
chmod 664 /etc/idrive360crontab.json

if [ -x /opt/IDrive360/idrive360-client ] && [ ! -f /opt/IDrive360/idrive360-client.real ]; then
    mv /opt/IDrive360/idrive360-client /opt/IDrive360/idrive360-client.real
    printf '#!/bin/bash\nexec /opt/IDrive360/idrive360-client.real --no-sandbox "$@"\n' \
        > /opt/IDrive360/idrive360-client
    chmod +x /opt/IDrive360/idrive360-client
fi

export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp &

exec /etc/idrive360cron --cron
