#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ImageView.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOCALIZATION_BUNDLE="$ROOT_DIR/.build/release/ImageView_ImageViewApp.bundle"

swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/ImageView" "$MACOS_DIR/ImageView"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/ImageView.icns" "$RESOURCES_DIR/ImageView.icns"
cp -R "$LOCALIZATION_BUNDLE" "$RESOURCES_DIR/ImageView_ImageViewApp.bundle"
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
chflags nohidden "$APP_DIR"

echo "$APP_DIR"
