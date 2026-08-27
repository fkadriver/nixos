#!/bin/bash
# One-time setup for the nas01-backup Ubuntu 24.04 VM (IDrive360 backup agent).
# Run as root on nas01: sudo bash /etc/nas01-backup/setup.sh
#
# What this does:
#   1. Downloads Ubuntu 24.04 cloud image
#   2. Creates a 20 GB qcow2 VM disk
#   3. Builds a cloud-init ISO (installs LXDE + VNC + IDrive360 deps on first boot)
#   4. Defines the VM in libvirt and starts it
#
# After cloud-init completes (~5 min): the VM joins the tailnet as its own node
# (MagicDNS: nas01-backup), so SSH is reachable directly from any tailnet machine:
#   - SSH:  ssh scott@nas01-backup.warthog-royal.ts.net
#
# Graphical console: lightdm auto-logs scott into LXDE on :0 at boot (no password —
# scott is in the nopasswdlogin group), which is what keeps IDrive360's GUI running
# unattended. Reach that desktop via QEMU's own console VNC, exposed on nas01's
# tailscale IP (see hosts/nas01/nas01-backup-domain.xml's <graphics> listen address
# and default.nix's `idrive-console-vnc` alias) — not from inside this VM at all.
# There is deliberately no in-guest VNC server (x11vnc/Xvfb) anymore: it duplicated
# the console, ran outside logind's seat management, and caused a PolicyKit
# "No session for pid" failure mode. See git history around 2026-08-24 for the
# full incident if this ever needs re-deriving.
#   Account password (SSH fallback only — console login needs none): changeme
#   — change with `passwd` after first login.
#
# To install IDrive360 inside the VM after it's up:
#   1. Copy the DEB into the VM: scp -o ProxyJump=nas01 /path/to/IDrive360_*.deb scott@<VM-IP>:
#   2. SSH into VM and run:  sudo apt install -y ./IDrive360_*.deb
#   3. The installer registers the device and starts the idrive360cron service.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

IMAGES_DIR=/var/lib/libvirt/images
VM_NAME=nas01-backup
DISK_SIZE=20G
BASE_IMAGE=$IMAGES_DIR/ubuntu-24.04-cloud.img
VM_DISK=$IMAGES_DIR/$VM_NAME.qcow2
CIDATA_ISO=$IMAGES_DIR/$VM_NAME-cidata.iso
UBUNTU_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

mkdir -p "$IMAGES_DIR"

echo "=== nas01-backup VM setup ==="
echo ""

# 1. Download Ubuntu 24.04 cloud image (cached; skip if already present)
if [ ! -f "$BASE_IMAGE" ]; then
    echo "[1/6] Downloading Ubuntu 24.04 cloud image (~600 MB)..."
    wget -O "$BASE_IMAGE.tmp" "$UBUNTU_URL"
    mv "$BASE_IMAGE.tmp" "$BASE_IMAGE"
    echo "      Saved: $BASE_IMAGE"
else
    echo "[1/6] Using cached cloud image: $BASE_IMAGE"
fi

# 2. Create VM disk (thin-provisioned copy-on-write from base image)
if [ ! -f "$VM_DISK" ]; then
    echo "[2/6] Creating ${DISK_SIZE} VM disk (copy-on-write)..."
    qemu-img create -F qcow2 -b "$BASE_IMAGE" -f qcow2 "$VM_DISK" "$DISK_SIZE"
    echo "      Created: $VM_DISK"
else
    echo "[2/6] VM disk already exists: $VM_DISK"
fi

# 3. Build cloud-init ISO
if [ ! -f "$CIDATA_ISO" ]; then
    echo "[3/6] Building cloud-init ISO..."

    # Derive scott's SSH public key from the Bitwarden-installed private key
    # (nas01 has no authorized_keys; keys come from Bitwarden via bitwarden-scott module)
    SCOTT_PUBKEY=$(ssh-keygen -y -f /home/scott/.ssh/id_ed25519_github 2>/dev/null || \
                   ssh-keygen -y -f /home/scott/.ssh/id_ed25519_legacy 2>/dev/null || true)
    if [ -z "$SCOTT_PUBKEY" ]; then
        echo "      WARNING: could not derive SSH public key — password auth only (changeme)"
    fi

    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    cat > "$TMPDIR/meta-data" << 'META'
instance-id: nas01-backup-1
local-hostname: nas01-backup
META

    cat > "$TMPDIR/user-data" << CLOUDINIT
#cloud-config
hostname: nas01-backup
manage_etc_hosts: true
ssh_pwauth: true

users:
  - name: scott
    uid: 1000
    groups: [sudo, adm, nopasswdlogin]
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: 'changeme'
    ssh_authorized_keys:
      - "$SCOTT_PUBKEY"

packages:
  - lxde-core
  - lxterminal
  - dbus-x11
  - curl
  - wget
  - ca-certificates
  - qemu-guest-agent

write_files:
  - path: /etc/modules-load.d/virtiofs.conf
    content: |
      virtiofs

  # Auto-login scott into LXDE on the real console (:0) at boot — this is what
  # keeps IDrive360's GUI running unattended, viewed via QEMU's own console VNC
  # (bound to nas01's tailscale IP; see nas01-backup-domain.xml) rather than a
  # second in-guest VNC server. No password: scott is in the nopasswdlogin group,
  # so lightdm's PAM stack (pam_succeed_if.so user ingroup nopasswdlogin) skips
  # the prompt for both autologin and any later manual re-login at the greeter.
  - path: /etc/lightdm/lightdm.conf.d/50-autologin.conf
    content: |
      [Seat:*]
      autologin-user=scott
      autologin-user-timeout=0
      autologin-session=LXDE

  # Wazuh visibility for IDrive360's backup status (never touches the
  # IDrive360 install itself — read-only).
  #
  # NOTE: an earlier version of this used three <localfile> blocks tailing
  # IDrive360's status files directly (log_format=json). Confirmed via live
  # testing (2026-07-28) that Wazuh's logcollector does NOT reliably detect
  # these files being rewritten in place — it missed every rewrite we tried,
  # including ones that grew the file, across a fresh wazuh-agent restart.
  # Replaced with a command wrapper that reads the file fresh on every run
  # instead (same pattern as wazuh-borg-status). See docs/idrive360.md and
  # wazuh-tailscale repo's config/wazuh_cluster/scripts/idrive360-status.sh
  # (canonical source of the script) + decoders/idrive360-command.xml +
  # rules/idrive360-command-rules.xml.
  - path: /usr/local/bin/wazuh-idrive360-status
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

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
      LATEST_LOG=$(ls -t /opt/IDrive360/idriveIt/user_profile/scott/*/Backup/DefaultBackupSet/LOGS/* \
                          /opt/IDrive360/idriveIt/user_profile/scott/*/CDP/DefaultBackupSet/LOGS/* \
                          2>/dev/null | head -1) || true

      FILES_BACKED_UP="unknown"
      SIZE_BACKED_UP="unknown"
      FILES_FAILED="unknown"
      LOG_NAME="none"

      if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
          LOG_NAME=$(basename "$LATEST_LOG")
          PARSED=$(grep -oP '[Bb]acked up now\s*:?\s*\K[0-9]+' "$LATEST_LOG" | head -1) || true
          if [ -n "$PARSED" ]; then FILES_BACKED_UP="$PARSED"; fi
          PARSED=$(grep -oP 'Size of backed up files:\s*\K[0-9.]+\s*[A-Za-z]+' "$LATEST_LOG" | head -1) || true
          if [ -n "$PARSED" ]; then SIZE_BACKED_UP="${PARSED// /}"; fi
          PARSED=$(grep -oP '[Ff]ailed to backup\s*:?\s*\K[0-9]+' "$LATEST_LOG" | head -1) || true
          if [ -n "$PARSED" ]; then FILES_FAILED="$PARSED"; fi
      fi

      echo "idrive360_backup: status=${STATUS} time=${TIME} files_backed_up=${FILES_BACKED_UP} size_backed_up=${SIZE_BACKED_UP} files_failed=${FILES_FAILED} log=${LOG_NAME}"

  # Idempotent — skips if already patched, so it's safe if re-run after a
  # manual restore.
  - path: /usr/local/bin/idrive360-wazuh-command.py
    permissions: '0755'
    content: |
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

runcmd:
  # Mount points for virtiofs shares
  - mkdir -p /pool /mnt /home/scott/git
  - echo 'pool    /pool           virtiofs  defaults,_netdev,nofail  0  0' >> /etc/fstab
  - echo 'mnt     /mnt            virtiofs  defaults,_netdev,nofail  0  0' >> /etc/fstab
  - echo 'git     /home/scott/git virtiofs  defaults,_netdev,nofail  0  0' >> /etc/fstab
  - mount -a 2>/dev/null || true

  # Disable screensaver/locker (no physical display; would lock VNC sessions)
  - apt-get remove -y xscreensaver xscreensaver-data xscreensaver-gl 2>/dev/null || true
  - mkdir -p /etc/xdg/autostart
  - printf '[Desktop Entry]\nHidden=true\n' > /etc/xdg/autostart/light-locker.desktop

  # Enable services
  - systemctl daemon-reload
  - systemctl enable qemu-guest-agent.service
  - systemctl start qemu-guest-agent.service
  - systemctl restart lightdm

  # Wazuh agent (monitoring for this VM / IDrive360). Installs and points at
  # the manager, but does NOT enroll — that needs the enrollment password,
  # which isn't baked into this cloud-init image. After first boot, run:
  #   sudo /var/ossec/bin/agent-auth -m wazuh.warthog-royal.ts.net -P '<password>' -A nas01-backup
  #   sudo systemctl enable --now wazuh-agent
  # (password: bw get item "Wazuh Agent Enrollment" — same secret nas01 itself uses)
  - curl -sS -o /tmp/wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.5-1_amd64.deb
  - WAZUH_MANAGER='wazuh.warthog-royal.ts.net' dpkg -i /tmp/wazuh-agent.deb
  - python3 /usr/local/bin/idrive360-wazuh-command.py
CLOUDINIT

    cloud-localds "$CIDATA_ISO" "$TMPDIR/user-data" "$TMPDIR/meta-data"
    echo "      Created: $CIDATA_ISO"
else
    echo "[3/6] Cloud-init ISO already exists: $CIDATA_ISO"
fi

# 4. Define the VM in libvirt
echo "[4/6] Defining VM in libvirt..."
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "      VM already defined — skipping (run 'virsh undefine $VM_NAME' to redefine)"
else
    virsh define /etc/nas01-backup/domain.xml
    echo "      VM defined from /etc/nas01-backup/domain.xml"
fi

# 5. Ensure the default NAT network is running
echo "[5/6] Ensuring libvirt default network is up..."
virsh net-start default 2>/dev/null && echo "      Started default network" || echo "      Default network already running"
virsh net-autostart default 2>/dev/null || true

# 6. Start the VM and enable autostart
echo "[6/6] Starting VM..."
if virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; then
    echo "      VM already running"
else
    virsh start "$VM_NAME"
    virsh autostart "$VM_NAME"
    echo "      VM started and set to autostart"
fi

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Cloud-init is now running inside the VM. Allow ~5 minutes for package install."
echo ""
echo "Monitor boot progress:"
echo "  virsh console nas01-backup          (Ctrl+] to detach)"
echo ""
echo "Once cloud-init finishes:"
VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 || true)
if [ -n "$VM_IP" ]; then
    echo "  VM NAT IP: $VM_IP  (only routable on nas01)"
fi
echo "  Reach it directly over the tailnet (VM is its own node, MagicDNS: nas01-backup):"
echo "  SSH:      ssh scott@nas01-backup.warthog-royal.ts.net"
echo "  Console:  idrive-console-vnc   (QEMU's own console VNC, on nas01's tailscale"
echo "            IP — scott auto-logs into LXDE, no password needed)"
echo "  SSH password fallback: changeme  — change with passwd"
echo ""
echo "To install IDrive360:"
echo "  1. Get the DEB download link from the IDrive360 web console"
echo "  2. wget -P ~ '<DEB-URL>'"
echo "  3. sudo apt install -y ~/IDrive360_*.deb"
