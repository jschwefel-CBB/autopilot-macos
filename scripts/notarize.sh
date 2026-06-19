#!/bin/bash
# Submit a tarball to Apple's notarization service and wait for approval.
#
# Usage: scripts/notarize.sh <path-to-tarball>
#
# Credentials — two modes:
#   Keychain profile (recommended for local dev):
#     xcrun notarytool store-credentials "autopilot-notary" \
#       --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
#       --password "$APPLE_APP_PASSWORD"
#     Then set NOTARY_KEYCHAIN_PROFILE=autopilot-notary in your env.
#
#   Env vars (for CI):
#     APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD must be set.
set -euo pipefail

TARBALL="${1:?usage: scripts/notarize.sh <path-to-tarball>}"
[ -f "$TARBALL" ] || { echo "ERROR: not found: $TARBALL" >&2; exit 1; }

if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  CREDS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  CREDS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  echo "==> Notarization credentials not found (APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD, or NOTARY_KEYCHAIN_PROFILE). Skipping." >&2
  exit 0
fi

echo "==> Submitting for notarization: $TARBALL"
xcrun notarytool submit "$TARBALL" "${CREDS[@]}" --wait --output-format json | tee /tmp/notary-result.json

STATUS="$(python3 -c "import json,sys; print(json.load(open('/tmp/notary-result.json'))['status'])")"
if [ "$STATUS" != "Accepted" ]; then
  echo "ERROR: notarization failed (status: $STATUS)" >&2
  xcrun notarytool log "$(python3 -c "import json,sys; print(json.load(open('/tmp/notary-result.json'))['id'])")" "${CREDS[@]}" >&2
  exit 1
fi
echo "==> Notarization accepted."
