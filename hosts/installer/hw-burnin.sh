#!/usr/bin/env bash
# Hardware burn-in / bring-up validation, run from a NixOS live/installer
# environment (or any NixOS system) before trusting new or used hardware
# with an OS install or production data. Hardware detection is fully
# generic — CPU count, disks, NICs, BMC are all auto-detected, nothing
# here is specific to any one server model.
#
# Exercises CPU + RAM under sustained load, runs SMART extended self-tests
# on every attached disk, and checks dmesg + the BMC/IPMI hardware log
# (iDRAC, iLO, etc.) for faults — catches marginal/failing components
# before they become a production incident.
#
# Usage (as root, e.g. on tty1 of the installer):
#   /etc/hw-burnin.sh [duration_minutes]   # default 240 (4h)
#
# If logs would only land on ephemeral storage (e.g. the tmpfs root of a
# live installer with no disk installed/mounted yet), this script offers
# to also stream them to a remote rsyslog server so they survive a reboot
# — and survive the box itself crashing mid-run, which is exactly the
# failure mode burn-in exists to catch. Files are shipped as they're
# generated (one-shot files immediately, the files that grow throughout
# the soak via a live `tail -F` follower), not batched at the end, so
# whatever happened before a crash is already on the remote server.
# Answer the prompt, or set REMOTE_LOG_HOST (and optionally
# REMOTE_LOG_PORT, default 514) beforehand to skip the prompt:
#   REMOTE_LOG_HOST=192.168.1.10 /etc/hw-burnin.sh
#
# What this does NOT cover — do these manually:
#   - PSU redundancy: pull one power cord while this is running under load,
#     confirm no interruption and that the BMC/front panel reports the fault.
#   - A dedicated MemTest86+ pass. stress-ng + a live kernel can't rule out
#     everything a purpose-built memory tester can — run MemTest86+ from
#     its own boot media before or after this script if you want that
#     level of confidence in the RAM.

set -uo pipefail  # no -e: keep going through failures so the report is complete

DURATION_MIN="${1:-240}"
LOG_DIR="/root/burnin-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.txt"

# --- Remote logging: offer it when the root filesystem is ephemeral ---
REMOTE_LOG_HOST="${REMOTE_LOG_HOST:-}"
REMOTE_LOG_PORT="${REMOTE_LOG_PORT:-514}"
ROOTFS_TYPE=$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)

case "$ROOTFS_TYPE" in
  tmpfs|ramfs|overlay)
    if [ -z "$REMOTE_LOG_HOST" ] && [ -t 0 ]; then
      echo "Root filesystem is '$ROOTFS_TYPE' — logs in $LOG_DIR won't survive a reboot."
      read -r -p "Also stream logs to a remote rsyslog server so they're preserved? (y/N): " ans
      if [[ "$ans" =~ ^[Yy] ]]; then
        read -r -p "Remote syslog host/IP: " REMOTE_LOG_HOST
        read -r -p "Remote syslog port [514]: " remote_port_in
        REMOTE_LOG_PORT="${remote_port_in:-514}"
      fi
    elif [ -z "$REMOTE_LOG_HOST" ]; then
      echo "Root filesystem is '$ROOTFS_TYPE' and no REMOTE_LOG_HOST set — logs in $LOG_DIR won't survive a reboot."
    fi
    ;;
esac

remote_log_line() {
  # $1 = tag, $2 = message
  [ -n "$REMOTE_LOG_HOST" ] || return 0
  logger -n "$REMOTE_LOG_HOST" -P "$REMOTE_LOG_PORT" -T -t "$1" -- "$2" 2>/dev/null || true
}

remote_log_file() {
  # $1 = tag, $2 = file — ships every line of $2 (as it exists right now)
  [ -n "$REMOTE_LOG_HOST" ] || return 0
  [ -f "$2" ] || return 0
  logger -n "$REMOTE_LOG_HOST" -P "$REMOTE_LOG_PORT" -T -t "$1" -f "$2" 2>/dev/null || true
}

declare -a FOLLOWER_PIDS=()

start_follower() {
  # $1 = tag, $2 = file — tails a growing file live, shipping new lines as
  # they're appended for as long as the file keeps being written to.
  [ -n "$REMOTE_LOG_HOST" ] || return 0
  touch "$2"
  ( tail -n0 -F "$2" 2>/dev/null | while IFS= read -r line; do
      logger -n "$REMOTE_LOG_HOST" -P "$REMOTE_LOG_PORT" -T -t "$1" -- "$line" 2>/dev/null
    done ) &
  FOLLOWER_PIDS+=("$!")
}

stop_followers() {
  [ "${#FOLLOWER_PIDS[@]}" -eq 0 ] && return 0
  for pid in "${FOLLOWER_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait "${FOLLOWER_PIDS[@]}" 2>/dev/null || true
  FOLLOWER_PIDS=()
}
trap stop_followers EXIT

log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo "$msg" | tee -a "$SUMMARY"
  remote_log_line "hw-burnin-summary" "$msg"
}

log "=== Burn-in starting: ${DURATION_MIN}m CPU+RAM soak + SMART extended self-tests ==="
log "Logs: $LOG_DIR"
if [ -n "$REMOTE_LOG_HOST" ]; then
  log "Streaming to $REMOTE_LOG_HOST:$REMOTE_LOG_PORT as files are generated (tag prefix hw-burnin-)"
fi

# --- Hardware inventory ---
log ""
log "--- CPU ---"
lscpu | tee "$LOG_DIR/lscpu.txt" | grep -E "Model name|Socket|Core|Thread" | tee -a "$SUMMARY" >/dev/null
remote_log_file "hw-burnin-lscpu" "$LOG_DIR/lscpu.txt"

log ""
log "--- Memory ---"
free -h | tee -a "$SUMMARY"
if command -v dmidecode >/dev/null; then
  dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Manufacturer|Locator" | grep -v "No Module" > "$LOG_DIR/dmidecode-memory.txt"
  remote_log_file "hw-burnin-dmidecode_memory" "$LOG_DIR/dmidecode-memory.txt"
fi

log ""
log "--- Storage controller ---"
lspci | grep -iE "sas|raid|lsi|avago|broadcom" | tee -a "$SUMMARY"

log ""
log "--- Disks ---"
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN | tee -a "$SUMMARY"

log ""
log "--- Network interfaces ---"
ip -br link | tee -a "$SUMMARY"

# --- BMC/IPMI hardware event log — used gear may have pre-existing faults ---
log ""
log "--- BMC/IPMI hardware log (last 40 entries) ---"
if command -v ipmitool >/dev/null && ipmitool sel elist >/dev/null 2>&1; then
  ipmitool sel elist | tail -40 > "$LOG_DIR/ipmi-sel.txt"
  cat "$LOG_DIR/ipmi-sel.txt" >> "$SUMMARY"
  remote_log_file "hw-burnin-ipmi_sel" "$LOG_DIR/ipmi-sel.txt"
else
  log "  ipmitool/SEL not accessible from this environment — check the BMC web UI's hardware/lifecycle log separately"
fi

# --- SMART extended self-test on every disk (non-destructive, safe with data present) ---
log ""
log "--- Starting SMART extended self-tests (background, non-destructive) ---"
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')
for d in $DISKS; do
  smartctl -t long "/dev/$d" > "$LOG_DIR/smart-$d.txt" 2>&1
  remote_log_file "hw-burnin-smart_$d" "$LOG_DIR/smart-$d.txt"
  log "  started extended self-test on /dev/$d"
done

# --- CPU + RAM stress soak ---
log ""
log "--- stress-ng: CPU + RAM for ${DURATION_MIN}m (sampling temps every 5m) ---"
CORES=$(nproc)
start_follower "hw-burnin-stress_ng_log" "$LOG_DIR/stress-ng.log"
start_follower "hw-burnin-temps_log" "$LOG_DIR/temps.log"
stress-ng --cpu "$CORES" --vm 2 --vm-bytes 80% --metrics-brief \
  --timeout "${DURATION_MIN}m" --log-file "$LOG_DIR/stress-ng.log" &
STRESS_PID=$!

while kill -0 "$STRESS_PID" 2>/dev/null; do
  {
    echo "--- $(date) ---"
    sensors 2>/dev/null || echo "(no sensors data — run sensors-detect, or check chassis temps via the BMC)"
  } >> "$LOG_DIR/temps.log"
  sleep 300
done
wait "$STRESS_PID"
STRESS_RC=$?
if [ "$STRESS_RC" -eq 0 ]; then
  log "stress-ng completed cleanly — no crash/OOM during the ${DURATION_MIN}m soak"
else
  log "stress-ng exited with code $STRESS_RC — check $LOG_DIR/stress-ng.log"
fi

# --- Poll SMART tests to completion ---
log ""
log "--- Waiting for SMART extended self-tests to finish ---"
for d in $DISKS; do
  while smartctl -c "/dev/$d" 2>/dev/null | grep -q "Self-test routine in progress"; do
    sleep 60
  done
  smartctl -a "/dev/$d" >> "$LOG_DIR/smart-$d.txt" 2>&1
  remote_log_file "hw-burnin-smart_$d" "$LOG_DIR/smart-$d.txt"
  if grep -qE "test result: PASSED|without error" "$LOG_DIR/smart-$d.txt"; then
    log "  /dev/$d: SMART extended self-test PASSED"
  else
    log "  /dev/$d: check $LOG_DIR/smart-$d.txt — may have FAILED, or self-test isn't supported over this transport"
  fi
done

# --- Hardware errors surfaced during the soak ---
log ""
log "--- Checking dmesg for hardware errors during burn-in ---"
if dmesg -T | grep -iE "mce|machine check|edac|ata error|reset|i/o error|pcie.*aer|correctable error|uncorrectable" > "$LOG_DIR/dmesg-errors.txt" && [ -s "$LOG_DIR/dmesg-errors.txt" ]; then
  log "  FOUND potential hardware errors in dmesg — see $LOG_DIR/dmesg-errors.txt"
else
  log "  No MCE/EDAC/ATA/PCIe error patterns found in dmesg"
fi
remote_log_file "hw-burnin-dmesg_errors" "$LOG_DIR/dmesg-errors.txt"

# stress-ng.log/temps.log were followed live throughout the soak above —
# stop the followers now that nothing more will be appended to them.
stop_followers

log ""
log "=== Burn-in complete. Full logs in $LOG_DIR ==="
log "Manual checks still needed:"
log "  - Pull-test each PSU under load (confirm failover + BMC/front-panel alert)"
log "  - Review $LOG_DIR/ipmi-sel.txt (or the BMC's lifecycle/event log) for pre-existing faults"
log "  - Consider a standalone MemTest86+ pass for the most thorough RAM check"
