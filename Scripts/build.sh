#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CONFIGURATION="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
swift build -c "$CONFIGURATION" --disable-sandbox
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --disable-sandbox)"
APP="$PWD/dist/Fold.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Fold" "$APP/Contents/MacOS/Fold"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/Fold.icns ]]; then cp Resources/Fold.icns "$APP/Contents/Resources/Fold.icns"; fi
codesign --force --sign - "$APP"
print "Built $APP"
