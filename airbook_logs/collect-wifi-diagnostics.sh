#!/usr/bin/env bash
# WiFi Diagnostic Script for NixOS Installer on MacBook Air
# Run this script and copy all generated .log files to a USB drive for analysis

set -euo pipefail

LOGDIR="$HOME/wifi-diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

echo "Collecting WiFi diagnostics to $LOGDIR..."

# Network interfaces
echo "=== Network Interfaces ===" | tee "$LOGDIR/00-summary.log"
ip link show > "$LOGDIR/ip-link.log" 2>&1
ip addr show > "$LOGDIR/ip-addr.log" 2>&1
echo "Network interfaces saved" | tee -a "$LOGDIR/00-summary.log"

# Kernel modules
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== Kernel Modules ===" | tee -a "$LOGDIR/00-summary.log"
lsmod | grep -E "(wl|broadcom|b43|bcm)" > "$LOGDIR/lsmod-wifi.log" 2>&1 || echo "No WiFi modules found" > "$LOGDIR/lsmod-wifi.log"
lsmod > "$LOGDIR/lsmod-all.log" 2>&1
echo "Kernel modules saved" | tee -a "$LOGDIR/00-summary.log"

# rfkill status
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== RF Kill Status ===" | tee -a "$LOGDIR/00-summary.log"
rfkill list > "$LOGDIR/rfkill.log" 2>&1
echo "RF kill status saved" | tee -a "$LOGDIR/00-summary.log"

# dmesg - WiFi related
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== Kernel Messages ===" | tee -a "$LOGDIR/00-summary.log"
dmesg | grep -i broadcom > "$LOGDIR/dmesg-broadcom.log" 2>&1 || echo "No Broadcom messages" > "$LOGDIR/dmesg-broadcom.log"
dmesg | grep -i "wl\|wlan\|wifi" > "$LOGDIR/dmesg-wifi.log" 2>&1 || echo "No WiFi messages" > "$LOGDIR/dmesg-wifi.log"
dmesg | grep -i firmware > "$LOGDIR/dmesg-firmware.log" 2>&1 || echo "No firmware messages" > "$LOGDIR/dmesg-firmware.log"
dmesg | grep -i "eth0" > "$LOGDIR/dmesg-eth0.log" 2>&1 || echo "No eth0 messages" > "$LOGDIR/dmesg-eth0.log"
dmesg > "$LOGDIR/dmesg-full.log" 2>&1
echo "Kernel messages saved" | tee -a "$LOGDIR/00-summary.log"

# NetworkManager
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== NetworkManager ===" | tee -a "$LOGDIR/00-summary.log"
systemctl status NetworkManager > "$LOGDIR/nm-status.log" 2>&1 || true
nmcli device status > "$LOGDIR/nmcli-device-status.log" 2>&1 || true
nmcli device show > "$LOGDIR/nmcli-device-show.log" 2>&1 || true
nmcli general status > "$LOGDIR/nmcli-general.log" 2>&1 || true
nmcli device wifi list > "$LOGDIR/nmcli-wifi-list.log" 2>&1 || echo "No WiFi networks found" > "$LOGDIR/nmcli-wifi-list.log"
echo "NetworkManager status saved" | tee -a "$LOGDIR/00-summary.log"

# wpa_supplicant
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== wpa_supplicant ===" | tee -a "$LOGDIR/00-summary.log"
systemctl status wpa_supplicant > "$LOGDIR/wpa-supplicant-status.log" 2>&1 || echo "wpa_supplicant not running" > "$LOGDIR/wpa-supplicant-status.log"
ps aux | grep wpa_supplicant > "$LOGDIR/wpa-supplicant-process.log" 2>&1 || true
echo "wpa_supplicant status saved" | tee -a "$LOGDIR/00-summary.log"

# Journal logs
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== System Journals ===" | tee -a "$LOGDIR/00-summary.log"
journalctl -u NetworkManager -n 100 --no-pager > "$LOGDIR/journal-networkmanager.log" 2>&1 || true
journalctl -u wpa_supplicant -n 100 --no-pager > "$LOGDIR/journal-wpa-supplicant.log" 2>&1 || true
journalctl -u systemd-networkd -n 50 --no-pager > "$LOGDIR/journal-networkd.log" 2>&1 || true
journalctl -k | grep -i "wl\|wlan\|broadcom\|wifi\|eth0" > "$LOGDIR/journal-kernel-wifi.log" 2>&1 || echo "No WiFi kernel messages" > "$LOGDIR/journal-kernel-wifi.log"
echo "Journal logs saved" | tee -a "$LOGDIR/00-summary.log"

# udev info
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== udev Information ===" | tee -a "$LOGDIR/00-summary.log"
for iface in /sys/class/net/*; do
    ifname=$(basename "$iface")
    if [ "$ifname" != "lo" ]; then
        udevadm info "$iface" > "$LOGDIR/udev-${ifname}.log" 2>&1 || true
    fi
done
echo "udev information saved" | tee -a "$LOGDIR/00-summary.log"

# PCI devices
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== Hardware Information ===" | tee -a "$LOGDIR/00-summary.log"
lspci | grep -i network > "$LOGDIR/lspci-network.log" 2>&1 || echo "No network devices" > "$LOGDIR/lspci-network.log"
lspci -v | grep -A 20 -i network > "$LOGDIR/lspci-network-verbose.log" 2>&1 || true
echo "Hardware information saved" | tee -a "$LOGDIR/00-summary.log"

# NetworkManager connection profiles
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== NetworkManager Profiles ===" | tee -a "$LOGDIR/00-summary.log"
nmcli connection show > "$LOGDIR/nmcli-connections.log" 2>&1 || true
if [ -d /etc/NetworkManager/system-connections ]; then
    ls -la /etc/NetworkManager/system-connections/ > "$LOGDIR/nm-profiles-list.log" 2>&1 || true
fi
echo "NetworkManager profiles saved" | tee -a "$LOGDIR/00-summary.log"

# Routing and DNS
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== Network Configuration ===" | tee -a "$LOGDIR/00-summary.log"
ip route show > "$LOGDIR/ip-route.log" 2>&1 || true
cat /etc/resolv.conf > "$LOGDIR/resolv.conf.log" 2>&1 || true
echo "Network configuration saved" | tee -a "$LOGDIR/00-summary.log"

# Summary
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "=== Collection Complete ===" | tee -a "$LOGDIR/00-summary.log"
echo "All diagnostics saved to: $LOGDIR" | tee -a "$LOGDIR/00-summary.log"
echo "" | tee -a "$LOGDIR/00-summary.log"
echo "Copy this entire directory to a USB drive:" | tee -a "$LOGDIR/00-summary.log"
echo "  mkdir -p /mnt/usb" | tee -a "$LOGDIR/00-summary.log"
echo "  mount /dev/sdX1 /mnt/usb  # Replace sdX1 with your USB device" | tee -a "$LOGDIR/00-summary.log"
echo "  cp -r $LOGDIR /mnt/usb/" | tee -a "$LOGDIR/00-summary.log"
echo "  umount /mnt/usb" | tee -a "$LOGDIR/00-summary.log"

# Final message
echo ""
echo "==================================="
echo "Diagnostic collection complete!"
echo "Directory: $LOGDIR"
echo "Total files: $(ls -1 "$LOGDIR" | wc -l)"
echo "==================================="
