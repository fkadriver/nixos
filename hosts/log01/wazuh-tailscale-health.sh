#!/usr/bin/env bash
# Tailscale node health poller.
#
# Emits one 'tailscale_health: check=self ...' line for this node's own
# tailscaled backend state, plus one 'tailscale_peer: ...' line per peer in
# the tailnet (from `tailscale status --json`, run locally — no API token
# needed, unlike github-ci-status.sh). Modeled on the same "one line per
# check, always emit something" shape as borg/github-ci-status.
#
# Deploy to /var/ossec/scripts/wazuh-tailscale-health on the agent (see
# borg-status.sh's deployment note in README).
#
# Requires: tailscale CLI (already present wherever tailscaled runs), jq,
# GNU date (for `date -d`, used to compute days-until-expiry).
#
# Field values are single tokens (spaces -> underscores in hostnames) —
# see opnsense-filterlog.xml/github-ci-status.sh notes on why OS_Regex
# can't reliably capture space-containing values.
#
# Canonical/documented copy lives in wazuh-tailscale's
# config/wazuh_cluster/scripts/tailscale-health-status.sh — this is a
# synced duplicate so NixOS's flake (pure eval) can deploy it without
# reading outside its own source tree, same as github-ci-status.sh.

set -uo pipefail

STATUS=$(tailscale status --json 2>&1)
if ! echo "$STATUS" | jq -e . >/dev/null 2>&1; then
  echo "tailscale_health: check=self status=ERROR error=status_command_failed"
  exit 0
fi

BACKEND_STATE=$(echo "$STATUS" | jq -r '.BackendState')
echo "tailscale_health: check=self backend_state=${BACKEND_STATE}"

NOW_EPOCH=$(date +%s)
KEY_EXPIRY_WARN_DAYS=14

echo "$STATUS" | jq -r '.Peer[] | [.HostName, .Online, (.KeyExpiry // "never"), (.LastSeen // "never"), .OS] | @tsv' |
while IFS=$'\t' read -r name online key_expiry last_seen os; do
  name_safe=$(echo "$name" | tr ' ' '_')
  status="ok"
  expiry_days="NA"

  if [ "$key_expiry" != "never" ] && [ "$key_expiry" != "0001-01-01T00:00:00Z" ]; then
    expiry_epoch=$(date -d "$key_expiry" +%s 2>/dev/null || echo "")
    if [ -n "$expiry_epoch" ]; then
      expiry_days=$(( (expiry_epoch - NOW_EPOCH) / 86400 ))
      if [ "$expiry_days" -lt 0 ]; then
        status="key_expired"
      elif [ "$expiry_days" -lt "$KEY_EXPIRY_WARN_DAYS" ]; then
        status="key_expiring_soon"
      fi
    fi
  fi

  echo "tailscale_peer: name=${name_safe} online=${online} os=${os} key_expiry=${key_expiry} expiry_days=${expiry_days} status=${status} last_seen=${last_seen}"
done
