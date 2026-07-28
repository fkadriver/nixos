#!/usr/bin/env bash
# Configure Syncthing on airbook-darwin via REST API.
# Idempotent — safe to re-run.
# Syncthing must be running: brew services start syncthing
#
# Usage: bash ~/git/nixos/hosts/airbook-darwin/syncthing-setup.sh

set -euo pipefail

BASE_URL="http://127.0.0.1:8384"
SYNCTHING_CONF="${HOME}/.local/state/syncthing"

# Device IDs (from syncthing-declarative.nix)
LATITUDE_ID="B4FAPKC-JTGMKTY-SE223WL-W2Y3VTT-JHU65E4-X3FUZ2C-4N62X4T-IRI75QZ"
NAS01_ID="3C5DWOE-HU34T3R-I74NNBJ-OOUELYG-HLSIUQN-L6GX52T-7GXPE5N-ZYPU4QO"
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
    echo "ERROR: Syncthing not ready. Run: brew services start syncthing"
    exit 1
fi

call() {
    local method="$1" path="$2"; shift 2
    curl -sf -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
        -X "$method" "${BASE_URL}${path}" "$@"
}

echo "Adding devices..."
call PUT "/rest/config/devices/${LATITUDE_ID}" -d '{
  "deviceID":  "'"${LATITUDE_ID}"'",
  "name":      "latitude",
  "addresses": ["tcp://latitude.warthog-royal.ts.net:22000"]
}'

call PUT "/rest/config/devices/${NAS01_ID}" -d '{
  "deviceID":  "'"${NAS01_ID}"'",
  "name":      "nas01",
  "addresses": ["tcp://nas01.warthog-royal.ts.net:22000"]
}'

call PUT "/rest/config/devices/${IPHONE_ID}" -d '{
  "deviceID":  "'"${IPHONE_ID}"'",
  "name":      "iphone",
  "addresses": ["tcp://scott-iphone.warthog-royal.ts.net:22000"]
}'

echo "Configuring folders..."
# Documents/Downloads/Photos: airbook syncs from home dir, shared with latitude + nas01
for SHARE in Documents Downloads Photos; do
    call PUT "/rest/config/folders/${SHARE}" -d '{
      "id":    "'"${SHARE}"'",
      "label": "'"${SHARE}"'",
      "path":  "'"${HOME}/${SHARE}"'",
      "type":  "sendreceive",
      "devices": [
        {"deviceID": "'"${LATITUDE_ID}"'"},
        {"deviceID": "'"${NAS01_ID}"'"}
      ],
      "versioning": {
        "type":             "simple",
        "params":           {"keep": "5"},
        "cleanupIntervalS": 3600
      },
      "fsWatcherEnabled": true
    }'
done

# tmp: airbook/latitude/iphone only (no nas01)
call PUT "/rest/config/folders/tmp" -d '{
  "id":    "tmp",
  "label": "tmp",
  "path":  "'"${HOME}/tmp"'",
  "type":  "sendreceive",
  "devices": [
    {"deviceID": "'"${LATITUDE_ID}"'"},
    {"deviceID": "'"${IPHONE_ID}"'"}
  ],
  "fsWatcherEnabled": true
}'

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
echo "Done. Syncthing on airbook-darwin is configured."
echo "  Folders: Documents, Downloads, Photos (~/), tmp (~/tmp)"
echo "  Peers: latitude, nas01, iphone (via Tailscale)"
echo ""
echo "Accept folder share invites from latitude after it rebuilds."
