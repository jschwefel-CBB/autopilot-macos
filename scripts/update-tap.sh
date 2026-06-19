#!/bin/bash
# Update the Homebrew tap formula with a new release.
#
# Usage: scripts/update-tap.sh <version> <sha256> <arch>
#   arch: arm64 or x86_64
#
# Env: TAP_REPO — SSH or HTTPS URL of the homebrew-autopilot repo
#      GITHUB_TOKEN — if set, uses HTTPS with token auth instead of SSH
set -euo pipefail

VERSION="${1:?usage: scripts/update-tap.sh <version> <sha256> <arch>}"
SHA256="${2:?}"
ARCH="${3:?}"   # arm64 or x86_64

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must be in N.N.N format, got: $VERSION" >&2
  exit 1
fi

TAP_REPO="${TAP_REPO:?TAP_REPO env var must point to homebrew-autopilot git URL}"
OWNER="jschwefel-CBB"   # update if repo owner changes
URL="https://github.com/${OWNER}/autopilot/releases/download/v${VERSION}/autopilot-${VERSION}-${ARCH}.tar.gz"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Cloning tap repo…"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  # CI: embed token in URL for HTTPS auth
  AUTH_URL="$(echo "$TAP_REPO" | sed "s|https://|https://x-access-token:${GITHUB_TOKEN}@|")"
  git clone "$AUTH_URL" "$TMPDIR/tap"
else
  git clone "$TAP_REPO" "$TMPDIR/tap"
fi

FORMULA="$TMPDIR/tap/Formula/autopilot.rb"
[ -f "$FORMULA" ] || { echo "ERROR: Formula/autopilot.rb not found in tap repo" >&2; exit 1; }

echo "==> Updating formula for ${ARCH} to v${VERSION}…"
# Update version field
sed -i '' "s|^  version \".*\"|  version \"${VERSION}\"|" "$FORMULA"

# Update arch-specific url + sha256 block.
# The formula uses on_arm/on_intel blocks; update the matching one.
if [ "$ARCH" = "arm64" ]; then
  # Replace url + sha256 inside the on_arm block
  python3 - "$FORMULA" "$URL" "$SHA256" << 'PY'
import sys, re
formula, url, sha = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(formula).read()
# Replace the url line inside on_arm do...end
text, n = re.subn(
  r'(on_arm do\s+url ")([^"]+)(")',
  lambda m: m.group(1) + url + m.group(3), text)
if n == 0:
    sys.exit(f"ERROR: pattern did not match in formula: on_arm url")
text, n = re.subn(
  r'(on_arm do\s+url "[^"]+"\s+sha256 ")([a-f0-9]+)(")',
  lambda m: m.group(1) + sha + m.group(3), text, flags=re.DOTALL)
if n == 0:
    sys.exit(f"ERROR: pattern did not match in formula: on_arm sha256")
open(formula, 'w').write(text)
print("arm64 url+sha updated")
PY
else
  python3 - "$FORMULA" "$URL" "$SHA256" << 'PY'
import sys, re
formula, url, sha = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(formula).read()
text, n = re.subn(
  r'(on_intel do\s+url ")([^"]+)(")',
  lambda m: m.group(1) + url + m.group(3), text)
if n == 0:
    sys.exit(f"ERROR: pattern did not match in formula: on_intel url")
text, n = re.subn(
  r'(on_intel do\s+url "[^"]+"\s+sha256 ")([a-f0-9]+)(")',
  lambda m: m.group(1) + sha + m.group(3), text, flags=re.DOTALL)
if n == 0:
    sys.exit(f"ERROR: pattern did not match in formula: on_intel sha256")
open(formula, 'w').write(text)
print("x86_64 url+sha updated")
PY
fi

cd "$TMPDIR/tap"
git config user.email "autopilot-release-bot@users.noreply.github.com"
git config user.name "AutoPilot Release Bot"
git add Formula/autopilot.rb
git diff --cached --stat
git commit -m "release: autopilot v${VERSION} (${ARCH})"
git push origin main
echo "==> Tap updated."
