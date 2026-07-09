#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ImageView.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --disable-sandbox --configuration release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/ImageView" "$MACOS_DIR/ImageView"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
