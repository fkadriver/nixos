#!/usr/bin/env bash
# Hardware burn-in / bring-up validation, run from the NixOS installer live
# environment BEFORE `nixos-install-helper.sh`. Written for the nas01 T330
# replacement (used server hardware — validate before trusting it with an
# OS install or the ZFS pool) but hardware detection is generic (CPU count,
# disks, NICs are all auto-detected, nothing T330-specific is hardcoded).
#
# Exercises CPU + RAM under sustained load, runs SMART extended self-tests
# on every attached disk, and checks dmesg + the BMC/iDRAC hardware log for
# faults — catches marginal/failing components before they become a
# production incident.
#
# Usage (as root, e.g. on tty1 of the installer):
#   /etc/t330-burnin.sh [duration_minutes]   # default 240 (4h)
#
# What this does NOT cover — do these manually:
#   - PSU redundancy: pull one power cord while this is running under load,
#     confirm no interruption and that iDRAC/front panel reports the fault.
#   - A dedicated MemTest86+ pass. stress-ng + a live kernel can't rule out
#     everything a purpose-built memory tester can — run MemTest86+ from
#     its own USB before or after this script if you want that level of
#     confidence in the RAM.

set -uo pipefail  # no -e: keep going through failures so the report is complete

DURATION_MIN="${1:-240}"
LOG_DIR="/root/burnin-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.txt"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$SUMMARY"; }

log "=== Burn-in starting: ${DURATION_MIN}m CPU+RAM soak + SMART extended self-tests ==="
log "Logs: $LOG_DIR"

# --- Hardware inventory ---
log ""
log "--- CPU ---"
lscpu | tee "$LOG_DIR/lscpu.txt" | grep -E "Model name|Socket|Core|Thread" | tee -a "$SUMMARY" >/dev/null

log ""
log "--- Memory ---"
free -h | tee -a "$SUMMARY"
if command -v dmidecode >/dev/null; then
  dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Manufacturer|Locator" | grep -v "No Module" > "$LOG_DIR/dmidecode-memory.txt"
fi

log ""
log "--- Storage controller (confirm HBA is visible, not the old RAID card) ---"
lspci | grep -iE "sas|raid|lsi|avago|broadcom" | tee -a "$SUMMARY"

log ""
log "--- Disks ---"
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN | tee -a "$SUMMARY"

log ""
log "--- Network interfaces ---"
ip -br link | tee -a "$SUMMARY"

# --- BMC/iDRAC hardware event log — used gear may have pre-existing faults ---
log ""
log "--- BMC/iDRAC hardware log (last 40 entries) ---"
if command -v ipmitool >/dev/null && ipmitool sel elist >/dev/null 2>&1; then
  ipmitool sel elist | tail -40 > "$LOG_DIR/ipmi-sel.txt"
  cat "$LOG_DIR/ipmi-sel.txt" >> "$SUMMARY"
else
  log "  ipmitool/SEL not accessible from this environment — check the iDRAC web UI's Lifecycle Log separately"
fi

# --- SMART extended self-test on every disk (non-destructive, safe with data present) ---
log ""
log "--- Starting SMART extended self-tests (background, non-destructive) ---"
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')
for d in $DISKS; do
  smartctl -t long "/dev/$d" > "$LOG_DIR/smart-$d.txt" 2>&1
  log "  started extended self-test on /dev/$d"
done

# --- CPU + RAM stress soak ---
log ""
log "--- stress-ng: CPU + RAM for ${DURATION_MIN}m (sampling temps every 5m) ---"
CORES=$(nproc)
stress-ng --cpu "$CORES" --vm 2 --vm-bytes 80% --metrics-brief \
  --timeout "${DURATION_MIN}m" --log-file "$LOG_DIR/stress-ng.log" &
STRESS_PID=$!

while kill -0 "$STRESS_PID" 2>/dev/null; do
  {
    echo "--- $(date) ---"
    sensors 2>/dev/null || echo "(no sensors data — run sensors-detect, or check chassis temps via iDRAC)"
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

log ""
log "=== Burn-in complete. Full logs in $LOG_DIR ==="
log "Manual checks still needed:"
log "  - Pull-test each PSU under load (confirm failover + iDRAC/front-panel alert)"
log "  - Review $LOG_DIR/ipmi-sel.txt (or iDRAC Lifecycle Log) for pre-existing faults"
log "  - Consider a standalone MemTest86+ pass for the most thorough RAM check"
