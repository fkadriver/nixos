#!/bin/bash
# IDrive360 container entrypoint (Rocky Linux 9 / RPM variant).
# /opt/IDrive360 is a persistent volume; /seed holds the installer .rpm.
# Container filesystem is ephemeral, so runtime deps and the cron binary
# are restored on every restart.
#
# First-boot flow (fresh registration):
#   1. Place IDrive360_<token>.rpm in /seed (no idrive360cron.bin in opt)
#   2. rpm -i registers the device and installs the engine into /opt/IDrive360
#   3. Entrypoint rescues the cron binary to /opt/IDrive360/idrive360cron.bin
#   4. All subsequent restarts use the rescued binary — no re-registration
#
# Recovery flow (idrive360cron.bin lost but rpm still in /seed):
#   - rpm -i is skipped (|| true) if the device is already registered
#   - Binary is extracted from rpm payload via rpm2cpio as fallback
set -e

if ! rpm -q dbus-libs >/dev/null 2>&1; then
    DNF_CACHE=/opt/IDrive360/.dnf-cache
    mkdir -p "$DNF_CACHE"
    dnf install -y \
        --allowerasing \
        --setopt=cachedir="$DNF_CACHE" \
        --setopt=keepcache=1 \
        --setopt=install_weak_deps=False \
        nss curl ca-certificates which tar cpio cronie procps-ng libnotify \
        expat popt xorg-x11-server-Xvfb net-tools \
        dbus-libs atk at-spi2-atk cups-libs gtk3 pango cairo \
        libXcomposite libXdamage libXfixes libxkbcommon \
        alsa-lib at-spi2-core
fi

# Rocky Linux 9 has no default UID 1000 user; create scott directly.
if ! id scott >/dev/null 2>&1; then
    useradd -u 1000 -m -s /bin/bash scott
fi

if [ ! -x /etc/idrive360cron ]; then
    if [ -f /opt/IDrive360/idrive360cron.bin ]; then
        # Fast path: binary was rescued to persistent volume after first install
        install -m 755 /opt/IDrive360/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif [ -f /seed/idrive360cron.bin ]; then
        # Legacy path: binary placed directly in seed
        install -m 755 /seed/idrive360cron.bin /usr/local/lib/idrive360cron
        ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
    elif ls /seed/IDrive360_*.rpm >/dev/null 2>&1; then
        # Bootstrap: run the installer to register with IDrive360 servers.
        # SUDO_USER=scott hints the user to the installer; the %post script
        # may still detect root — we patch the profile afterwards as a fallback.
        # Use || true: if the device is already registered the rpm returns
        # non-zero, but the binary files are already on the persistent volume.
        SUDO_USER=scott rpm -i /seed/IDrive360_*.rpm || true

        # Patch root→scott in profile and cache if installer detected root.
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

        # Rescue the cron binary from wherever the installer put it.
        if [ -x /etc/idrive360cron ]; then
            REAL_BIN=$(readlink -f /etc/idrive360cron 2>/dev/null || echo /etc/idrive360cron)
            install -m 755 "$REAL_BIN" /opt/IDrive360/idrive360cron.bin
        fi

        # Fallback: extract cron binary directly from the rpm payload.
        # This handles the case where the device is already registered (rpm -i
        # skipped) but idrive360cron.bin was lost from the persistent volume.
        if [ ! -x /opt/IDrive360/idrive360cron.bin ]; then
            echo "rpm -i skipped or failed; extracting cron binary from rpm payload..." >&2
            TMP_EXTRACT=$(mktemp -d)
            (cd "$TMP_EXTRACT" && rpm2cpio /seed/IDrive360_*.rpm | cpio -idm 2>/dev/null) || true
            RPM_CRON=$(find "$TMP_EXTRACT" -name "idrive360cron" -not -name "*.bin" -type f | head -1)
            if [ -n "$RPM_CRON" ] && [ -x "$RPM_CRON" ]; then
                install -m 755 "$RPM_CRON" /opt/IDrive360/idrive360cron.bin
            fi
            rm -rf "$TMP_EXTRACT"
        fi

        # Wire up /etc/idrive360cron from the rescued binary.
        if [ -x /opt/IDrive360/idrive360cron.bin ] && [ ! -x /etc/idrive360cron ]; then
            install -m 755 /opt/IDrive360/idrive360cron.bin /usr/local/lib/idrive360cron
            ln -sf /usr/local/lib/idrive360cron /etc/idrive360cron
        fi
    else
        echo "ERROR: no idrive360cron binary and no installer .rpm in /seed" >&2
        exit 1
    fi
fi

if [ ! -x /etc/idrive360cron ]; then
    echo "ERROR: could not install idrive360cron — check seed directory" >&2
    exit 1
fi

# Restore persistent schedule backup; scott-owned so the Python scheduler
# (uid 1000) can update nextschedule timestamps.
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

# Run cron as scott so the daemon finds the scott user profile.
# The RPM installer detects root; we patch idriveuser.txt root→scott above,
# and run as scott so the daemon's user lookup matches.
exec su -s /bin/bash scott -c "exec /etc/idrive360cron --cron"
