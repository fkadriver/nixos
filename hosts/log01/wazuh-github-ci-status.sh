#!/usr/bin/env bash
# GitHub Actions CI status poller.
#
# Emits one 'github_ci: ...' line per configured repo, read by the Wazuh
# manager as a command localfile (see shared/github-monitor/agent.conf).
# Modeled on wazuh-borg-status: same "one line per check, always emit
# something, never let one failure block the rest" shape.
#
# Deploy to /var/ossec/scripts/wazuh-github-ci-status on the agent (see
# borg-status.sh's deployment note in README — same /var/ossec/scripts/
# path requirement due to the bwrap FHS sandbox hiding /usr/local/bin).
#
# Requires:
#   - GH_TOKEN_FILE readable by the agent process — a fine-grained PAT
#     scoped to Actions:read on exactly the repos below (see README).
#   - curl and jq in the wazuh-agent FHS sandbox (see wazuh-agent.nix).
#     An earlier version hand-parsed JSON with grep/sed to avoid the jq
#     dependency — that broke on nested fields sharing a key name with the
#     top-level ones being extracted (e.g. head_commit.message colliding
#     with the API's top-level error "message" field) and on values
#     containing colons (timestamps). jq is one small Nix package; not
#     worth re-fighting hand-rolled JSON parsing for it.
#
# Only the LATEST run per repo is reported (not a history) — this is a
# point-in-time status check on a schedule (agent.conf frequency), not an
# event stream. A repo with zero workflow runs ever (confirmed for two of
# these four when this was built) reports status=no_runs.
#
# Canonical/documented copy lives in wazuh-tailscale's
# config/wazuh_cluster/scripts/github-ci-status.sh — this is a synced
# duplicate so NixOS's flake (pure eval) can deploy it without reading
# outside its own source tree, same as borg-backup.nix's inline copy of
# wazuh-borg-status. Keep the two in sync by hand if either changes.

set -uo pipefail

GH_TOKEN_FILE="${GH_TOKEN_FILE:-/run/bitwarden-secrets/github_actions_token}"
REPOS="fkadriver/tailnet fkadriver/Fortydeux-NixOS-System-Flake fkadriver/photoAlbumOrganizer fkadriver/SANS"

if [ ! -r "$GH_TOKEN_FILE" ]; then
  echo "github_ci: repo=- status=ERROR error=token_file_unreadable path=${GH_TOKEN_FILE}"
  exit 0
fi
GH_TOKEN=$(cat "$GH_TOKEN_FILE")

for repo in $REPOS; do
  response=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/actions/runs?per_page=1")

  if [ -z "$response" ]; then
    echo "github_ci: repo=${repo} status=ERROR error=no_response"
    continue
  fi

  # Field values are sanitized to single tokens (spaces -> underscores) —
  # Wazuh's OS_Regex has no reliable "match anything including spaces"
  # pattern (confirmed while building opnsense-filterlog.xml: `.` isn't a
  # wildcard there), so a human-readable message/workflow name with spaces
  # can't be captured as one regex group. Losing the exact spacing here is
  # a fine trade for the value actually being decodable.
  if ! echo "$response" | jq -e 'has("workflow_runs")' >/dev/null 2>&1; then
    err=$(echo "$response" | jq -r '(.message // "unrecognized_response")' | tr ' ' '_')
    echo "github_ci: repo=${repo} status=ERROR error=api_error message=${err}"
    continue
  fi

  run=$(echo "$response" | jq -c '.workflow_runs[0]')
  if [ "$run" = "null" ] || [ -z "$run" ]; then
    echo "github_ci: repo=${repo} status=no_runs"
    continue
  fi

  name=$(echo "$run" | jq -r '.name' | tr ' ' '_')
  status=$(echo "$run" | jq -r '.status')
  conclusion=$(echo "$run" | jq -r '.conclusion')
  run_number=$(echo "$run" | jq -r '.run_number')
  branch=$(echo "$run" | jq -r '.head_branch')
  updated=$(echo "$run" | jq -r '.updated_at')

  echo "github_ci: repo=${repo} workflow=${name} status=${status} conclusion=${conclusion} run=${run_number} branch=${branch} updated=${updated}"
done
