#!/bin/bash
# IDrive360 container entrypoint (Rocky Linux 9 / RPM variant).
# /opt/IDrive360 is a persistent volume; /seed holds the installer .rpm and
# the rescued idrive360cron binary.  Container filesystem is ephemeral, so
# runtime deps and the cron binary are restored on every restart.
#
# First-boot flow (fresh registration):
#   1. Place IDrive360_<token>.rpm in /seed (no idrive360cron.bin)
#   2. rpm -i registers the device and downloads the engine into /opt/IDrive360
#   3. Entrypoint rescues the cron binary to /opt/IDrive360/idrive360cron.bin
#   4. All subsequent restarts use the rescued binary — no re-registration
set -e

if ! rpm -q dbus-libs >/dev/null 2>&1; then
    DNF_CACHE=/opt/IDrive360/.dnf-cache
    mkdir -p "$DNF_CACHE"
    dnf install -y \
        --allowerasing \
        --setopt=cachedir="$DNF_CACHE" \
        --setopt=keepcache=1 \
        --setopt=install_weak_deps=False \
        nss curl ca-certificates which tar cronie libnotify \
        expat popt xorg-x11-server-Xvfb net-tools \
        dbus-libs atk at-spi2-atk cups-libs gtk3 pango cairo \
        libXcomposite libXdamage libXfixes libxkbcommon \
        alsa-lib at-spi2-core
fi

# Rocky Linux 9 has no default UID 1000 user; just create scott directly.
if ! id scott >/dev/null 2>&1; then
    useradd -u 1000 -m -s /bin/bash scott
fi

if [ ! -x /etc/idrive360cron ]; then
    # The binary refuses to run unless $0 is a symlink (vendor check).
    if [ -f /opt/IDrive360/idrive360cron.bin ]; then
        # Fast path: binary was rescued here after the first rpm install
        install -m 755 /opt/IDrive360/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif [ -f /seed/idrive360cron.bin ]; then
        # Legacy path: binary placed directly in seed
        install -m 755 /seed/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif ls /seed/IDrive360_*.rpm >/dev/null 2>&1; then
        # Fresh bootstrap: %post registers the device with the embedded token
        # and downloads the backup engine into /opt/IDrive360.
        # Set SUDO_USER so the installer picks scott; RPM %post may not inherit
        # the env, so we rename root->scott as a fallback.
        SUDO_USER=scott rpm -i /seed/IDrive360_*.rpm
        if [ -d /opt/IDrive360/idriveIt/user_profile/root ] && \
           [ ! -d /opt/IDrive360/idriveIt/user_profile/scott ]; then
            mv /opt/IDrive360/idriveIt/user_profile/root \
               /opt/IDrive360/idriveIt/user_profile/scott
            chown -R 1000:1000 /opt/IDrive360/idriveIt/user_profile/scott
        fi
        CACHE_FILE=/opt/IDrive360/idriveIt/cache/idriveuser.txt
        if [ -f "$CACHE_FILE" ] && grep -q '"root"' "$CACHE_FILE"; then
            sed -i 's/"root":/"scott":/g' "$CACHE_FILE"
        fi
        if [ -x /etc/idrive360cron ]; then
            REAL_BIN=$(readlink -f /etc/idrive360cron 2>/dev/null || echo /etc/idrive360cron)
            install -m 755 "$REAL_BIN" /opt/IDrive360/idrive360cron.bin
        fi
    else
        echo "ERROR: no idrive360cron binary and no installer .rpm in /seed" >&2
        exit 1
    fi
fi

# Restore persistent schedule backup; must be scott-owned so the Python
# scheduler (uid 1000) can update nextschedule timestamps.
if [ -s /opt/IDrive360/crontab.bak ] && [ ! -s /etc/idrive360crontab.json ]; then
    cp /opt/IDrive360/crontab.bak /etc/idrive360crontab.json
fi
touch /etc/idrive360crontab.json
chown scott:scott /etc/idrive360crontab.json
chmod 664 /etc/idrive360crontab.json

# Electron refuses to run as root without --no-sandbox; wrap the binary once.
if [ -x /opt/IDrive360/idrive360-client ] && [ ! -f /opt/IDrive360/idrive360-client.real ]; then
    mv /opt/IDrive360/idrive360-client /opt/IDrive360/idrive360-client.real
    printf '#!/bin/bash\nexec /opt/IDrive360/idrive360-client.real --no-sandbox "$@"\n' \
        > /opt/IDrive360/idrive360-client
    chmod +x /opt/IDrive360/idrive360-client
fi

export DISPLAY=:98
pkill Xvfb 2>/dev/null || true
rm -f /tmp/.X98-lock /tmp/.X11-unix/X98
Xvfb :98 -screen 0 1024x768x16 -nolisten tcp &

exec /etc/idrive360cron --cron
