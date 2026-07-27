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
# After cloud-init completes (~5 min):
#   - SSH:  ssh -J nas01 scott@$(virsh domifaddr nas01-backup | awk '/ipv4/{print $4}' | cut -d/ -f1)
#   - VNC:  ssh -L 5901:127.0.0.1:5901 nas01   then connect to localhost:5901
#     (or open a VNC viewer from the nas01 RDP/Openbox session: vncviewer localhost:1)
#   Default password for both SSH and VNC: changeme  — change it after first login.
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
    groups: [sudo, adm]
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: 'changeme'
    ssh_authorized_keys:
      - "$SCOTT_PUBKEY"

packages:
  - lxde-core
  - lxterm
  - x11vnc
  - xvfb
  - dbus-x11
  - curl
  - wget
  - ca-certificates
  - qemu-guest-agent

write_files:
  - path: /etc/modules-load.d/virtiofs.conf
    content: |
      virtiofs

  # Desktop session + VNC startup script
  - path: /usr/local/bin/start-vnc-desktop
    permissions: '0755'
    content: |
      #!/bin/bash
      # Kill any stale display
      pkill Xvfb 2>/dev/null || true
      rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
      sleep 1

      # Start virtual framebuffer
      Xvfb :1 -screen 0 1280x800x16 -nolisten tcp &
      sleep 2

      # Start LXDE on the virtual display
      export DISPLAY=:1
      dbus-launch --exit-with-session startlxde &
      sleep 3

      # Expose via VNC (reads ~/.vnc/passwd for password)
      exec x11vnc -display :1 -forever -rfbport 5901 -usepw -shared

  - path: /etc/systemd/system/vnc-desktop.service
    content: |
      [Unit]
      Description=LXDE desktop session with VNC
      After=network.target

      [Service]
      User=scott
      ExecStart=/usr/local/bin/start-vnc-desktop
      Restart=on-failure
      RestartSec=10

      [Install]
      WantedBy=multi-user.target

runcmd:
  # Mount points for virtiofs shares
  - mkdir -p /pool /mnt
  - echo 'pool    /pool   virtiofs  defaults,_netdev,nofail  0  0' >> /etc/fstab
  - echo 'mnt     /mnt    virtiofs  defaults,_netdev,nofail  0  0' >> /etc/fstab
  - mount -a 2>/dev/null || true

  # VNC password (change after first login with: vncpasswd)
  - mkdir -p /home/scott/.vnc
  - chown 1000:1000 /home/scott/.vnc
  - su - scott -c "x11vnc -storepasswd changeme ~/.vnc/passwd"
  - chmod 600 /home/scott/.vnc/passwd
  - chown 1000:1000 /home/scott/.vnc/passwd

  # Enable services
  - systemctl daemon-reload
  - systemctl enable vnc-desktop.service
  - systemctl enable qemu-guest-agent.service
  - systemctl start qemu-guest-agent.service
  - systemctl start vnc-desktop.service
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
    echo "  VM IP: $VM_IP"
    echo "  SSH:   ssh scott@$VM_IP            (or: ssh -J nas01 scott@$VM_IP from laptop)"
else
    echo "  Get VM IP: virsh domifaddr nas01-backup"
    echo "  SSH:       ssh scott@<VM-IP>"
fi
echo "  VNC:   From nas01 RDP/Openbox session: vncviewer localhost:1"
echo "         From laptop: ssh -L 5901:127.0.0.1:5901 nas01   then VNC to localhost:5901"
echo "  Default password (SSH + VNC): changeme  — change with passwd / vncpasswd"
echo ""
echo "To install IDrive360:"
echo "  1. Get the DEB download link from the IDrive360 web console"
echo "  2. wget -P ~ '<DEB-URL>'"
echo "  3. sudo apt install -y ~/IDrive360_*.deb"
