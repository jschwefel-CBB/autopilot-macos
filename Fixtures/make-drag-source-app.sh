#!/bin/bash
# Build the AutopilotDragSource helper and assemble it into a proper .app bundle
# so it launches as a real foreground GUI app (a bare Mach-O does not — and only
# a foreground app can originate a cross-process file drag).
#
# Output: <package .build>/AutopilotDragSource.app
#
# The macOS backend (FileDragSource) launches this helper to perform a real
# cross-process file drop. Tests point AUTOPILOT_DRAG_SOURCE at the built binary.
set -euo pipefail
cd "$(dirname "$0")/.."   # package root

swift build --product AutopilotDragSource
BINDIR="$(swift build --show-bin-path)"
BIN="$BINDIR/AutopilotDragSource"
APP="$BINDIR/AutopilotDragSource.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AutopilotDragSource"
cat > "$APP/Contents/Info.plist" <<'PL'
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

# Ad-hoc codesign so TCC/AX treats it as a stable identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
