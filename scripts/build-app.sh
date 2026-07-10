#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ImageView.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/ImageView" "$MACOS_DIR/ImageView"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/ImageView.icns" "$RESOURCES_DIR/ImageView.icns"
cp -R "$ROOT_DIR/Sources/ImageViewApp/Resources/en.lproj" "$RESOURCES_DIR/en.lproj"
cp -R "$ROOT_DIR/Sources/ImageViewApp/Resources/zh-Hans.lproj" "$RESOURCES_DIR/zh-Hans.lproj"

echo "$APP_DIR"
