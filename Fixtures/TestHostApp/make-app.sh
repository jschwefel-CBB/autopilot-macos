#!/bin/bash
# Build TestHostApp and assemble it into a proper .app bundle so it launches
# as a real GUI app with its own Accessibility tree (a bare Mach-O does not).
#
# Output: Fixtures/TestHostApp/.build/TestHostApp.app
set -euo pipefail
cd "$(dirname "$0")"

swift build
BIN="$(swift build --show-bin-path)/TestHostApp"
APP=".build/TestHostApp.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TestHostApp"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc codesign so TCC/AX treats it as a stable identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "$PWD/$APP"
