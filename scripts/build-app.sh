#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ImageView.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR"

# Resolve the products through SwiftPM rather than the .build/release convenience
# symlink: build engines move their output (the swiftbuild engine writes to
# .build/out/Products/Release), and a stale symlink would silently package old
# binaries and localization bundles.
BIN_DIR="$(swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE="$BIN_DIR/ImageView"
LOCALIZATION_BUNDLE="$BIN_DIR/ImageView_ImageViewApp.bundle"

if [ ! -x "$EXECUTABLE" ]; then
    echo "missing executable: $EXECUTABLE" >&2
    exit 1
fi
if [ ! -d "$LOCALIZATION_BUNDLE" ]; then
    echo "missing localization bundle: $LOCALIZATION_BUNDLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/ImageView"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/ImageView.icns" "$RESOURCES_DIR/ImageView.icns"
cp -R "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/ImageView_ImageViewApp.bundle"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
chflags nohidden "$APP_DIR"

echo "$APP_DIR"
