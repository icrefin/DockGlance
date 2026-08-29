#!/bin/bash
# Builds DockGlance.app (SwiftPM-only, ad-hoc signed) and a distributable zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
APP_NAME="DockGlance"
BUILD_DIR="$ROOT/dist"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c release (arm64)"
cd "$ROOT"
# SPM's incremental state has produced stale release binaries when debug
# and release builds interleave (binary older than sources while the
# build claims up-to-date). Always start from a clean slate so a release
# build can never ship old code.
swift package clean
swift build -c release

rm -rf "$APP" "$BUILD_DIR/$APP_NAME-$VERSION.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> assembling $APP_NAME.app"
cp "$ROOT/.build/release/DockGlance" "$APP/Contents/MacOS/DockGlance"
cp "$ROOT/scripts/DockGlance.icns" "$APP/Contents/Resources/DockGlance.icns"
sed "s|\${VERSION}|$VERSION|g" "$ROOT/scripts/Info.plist" > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> zipping"
(
    cd "$BUILD_DIR"
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip"
)
SHA="$(shasum -a 256 "$BUILD_DIR/$APP_NAME-$VERSION.zip" | cut -d' ' -f1)"
echo "==> $BUILD_DIR/$APP_NAME-$VERSION.zip  sha256=$SHA"

# Stamp the cask with the new sha.
CASK="$ROOT/Cask/dockglance.rb"
sed -i '' "s|sha256 \"[a-f0-9]*\"|sha256 \"$SHA\"|" "$CASK"
echo "==> updated $CASK"