#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/ImageView.app"
DESTINATION_APP="/Applications/ImageView.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/scripts/build-app.sh"

pkill -x ImageView 2>/dev/null || true
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

# Copying from an iCloud-backed workspace can attach Finder/File Provider
# metadata that invalidates a bundle signature. Remove it before final signing.
xattr -cr "$DESTINATION_APP"
codesign --force --sign - "$DESTINATION_APP"
chflags nohidden "$DESTINATION_APP"
"$LSREGISTER" -f "$DESTINATION_APP"

open -na "$DESTINATION_APP"
echo "$DESTINATION_APP"
