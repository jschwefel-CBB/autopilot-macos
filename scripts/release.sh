#!/bin/bash
# Build a release of the autopilot CLI + AutopilotMCP MCP server.
#
# Usage: scripts/release.sh <version>
#   e.g. scripts/release.sh 1.0.0
#
# Produces dist/autopilot-<version>-<arch>.tar.gz containing the autopilot CLI,
# the AutopilotMCP server, and the AutopilotDragSource.app helper (needed for
# real file drag-and-drop — the `drag` action's `toFiles`).
# Printing the SHA-256 of each tarball to stdout so callers can embed it.
#
# Signing is ad-hoc (codesign -s -). For notarization with a real Developer ID,
# use scripts/notarize.sh after this script.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
ARCH="$(uname -m)"   # arm64 or x86_64
DIST="dist"

echo "==> Building release binaries (${VERSION}, ${ARCH})…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
AUTOPILOT="${BIN_PATH}/autopilot"
MCP="${BIN_PATH}/AutopilotMCP"
DRAGSRC="${BIN_PATH}/AutopilotDragSource"
for f in "$AUTOPILOT" "$MCP" "$DRAGSRC"; do
  [ -x "$f" ] || { echo "ERROR: expected binary not found: $f" >&2; exit 1; }
done

rm -rf "$DIST"; mkdir -p "$DIST"
cp "$AUTOPILOT" "$DIST/autopilot"
cp "$MCP"        "$DIST/AutopilotMCP"

# The drag-source helper must ship as a proper .app so it launches as a real
# foreground GUI app (only a foreground app can originate a cross-process drag).
# FileDragSource locates it as AutopilotDragSource.app next to the autopilot binary.
DRAG_APP="$DIST/AutopilotDragSource.app"
mkdir -p "$DRAG_APP/Contents/MacOS"
cp "$DRAGSRC" "$DRAG_APP/Contents/MacOS/AutopilotDragSource"
cat > "$DRAG_APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AutopilotDragSource</string>
<key>CFBundleIdentifier</key><string>com.autopilot.dragsource</string>
<key>CFBundleName</key><string>AutopilotDragSource</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL

echo "==> Signing (ad-hoc)…"
codesign --force --sign - "$DIST/autopilot"
codesign --force --sign - "$DIST/AutopilotMCP"
codesign --force --sign - "$DRAG_APP"

TARBALL="${DIST}/autopilot-${VERSION}-${ARCH}.tar.gz"
echo "==> Packaging → ${TARBALL}"
tar -czf "$TARBALL" -C "$DIST" autopilot AutopilotMCP AutopilotDragSource.app

SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
echo "==> SHA-256: ${SHA}"
echo ""
echo "Artifact:  ${TARBALL}"
echo "SHA-256:   ${SHA}"
echo ""
echo "Next steps (manual — these publish):"
echo "  1. Notarize (if Developer ID):  scripts/notarize.sh $TARBALL"
echo "  2. Tag:  git tag v${VERSION} && git push origin v${VERSION}"
echo "  3. Create release:  gh release create v${VERSION} ${TARBALL} --title \"v${VERSION}\""
echo "  4. Update tap:  scripts/update-tap.sh ${VERSION} ${SHA} ${ARCH}"
