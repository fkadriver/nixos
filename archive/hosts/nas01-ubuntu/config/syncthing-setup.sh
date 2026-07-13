#!/usr/bin/env bash
# Configure Syncthing on nas01 via REST API.
# Idempotent — safe to re-run after apply.sh.
# Must run as scott (not root).
#
# Usage: bash ~/git/nixos/hosts/nas01/config/syncthing-setup.sh

set -euo pipefail

BASE_URL="http://127.0.0.1:8384"
SYNCTHING_CONF="${HOME}/.local/state/syncthing"
SYNC_BASE="${HOME}/syncthing"

# Device IDs (from syncthing-declarative.nix)
LATITUDE_ID="B4FAPKC-JTGMKTY-SE223WL-W2Y3VTT-JHU65E4-X3FUZ2C-4N62X4T-IRI75QZ"
AIRBOOK_ID="MIWPTKO-AAFMDLU-BBWGY74-VIR6B2Y-H5OQAV2-COC7RKI-MSS3ZLB-XYBLYQB"
IPHONE_ID="SDE4XUA-P5E6GZF-EMPGWPV-POTQWCO-2VJKNC3-T2CQMJ4-4OJQTEU-SSUNDA4"

# Wait for syncthing to be ready and get API key
echo "Waiting for Syncthing..."
API_KEY=""
for i in $(seq 1 30); do
    if [[ -f "${SYNCTHING_CONF}/config.xml" ]]; then
        API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' "${SYNCTHING_CONF}/config.xml" 2>/dev/null || true)
    fi
    if [[ -n "$API_KEY" ]] && curl -sf -H "X-API-Key: $API_KEY" "${BASE_URL}/rest/system/ping" >/dev/null 2>&1; then
        break
    fi
    sleep 2
    echo -n "."
done
echo

if [[ -z "$API_KEY" ]]; then
    echo "ERROR: Syncthing not ready. Is 'syncthing' service running?"
    exit 1
fi

call() {
    local method="$1" path="$2"; shift 2
    curl -sf -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
        -X "$method" "${BASE_URL}${path}" "$@"
}

echo "Creating sync directories..."
mkdir -p "${SYNC_BASE}"/{Documents,Downloads,Photos}

echo "Adding devices..."
call PUT "/rest/config/devices/${LATITUDE_ID}" -d '{
  "deviceID":  "'"${LATITUDE_ID}"'",
  "name":      "latitude",
  "addresses": ["tcp://latitude.warthog-royal.ts.net:22000"]
}'

call PUT "/rest/config/devices/${AIRBOOK_ID}" -d '{
  "deviceID":  "'"${AIRBOOK_ID}"'",
  "name":      "airbook-darwin",
  "addresses": ["tcp://airbook.warthog-royal.ts.net:22000"]
}'

echo "Configuring folders..."
# nas01 syncs to ~/syncthing/<SHARE>; no tmp (tmp is airbook/latitude/iphone only)
for SHARE in Documents Downloads Photos; do
    call PUT "/rest/config/folders/${SHARE}" -d '{
      "id":    "'"${SHARE}"'",
      "label": "'"${SHARE}"'",
      "path":  "'"${SYNC_BASE}/${SHARE}"'",
      "type":  "sendreceive",
      "devices": [
        {"deviceID": "'"${LATITUDE_ID}"'"},
        {"deviceID": "'"${AIRBOOK_ID}"'"}
      ],
      "versioning": {
        "type":             "simple",
        "params":           {"keep": "5"},
        "cleanupIntervalS": 3600
      },
      "fsWatcherEnabled": true
    }'
done

echo "Setting Tailscale-only network options..."
call PATCH "/rest/config/options" -d '{
  "globalAnnounceEnabled": false,
  "localAnnounceEnabled":  false,
  "relaysEnabled":         false,
  "natTraversalEnabled":   false
}'

echo "Restarting Syncthing to apply config..."
call POST "/rest/config/restart" -d '' > /dev/null

echo ""
echo "Done. Syncthing on nas01 is configured."
echo "  Sync root: ${SYNC_BASE}"
echo "  Folders: Documents, Downloads, Photos"
echo "  Peers: latitude, airbook-darwin (via Tailscale)"
echo ""
echo "Accept the folder share invites from latitude after it rebuilds."
