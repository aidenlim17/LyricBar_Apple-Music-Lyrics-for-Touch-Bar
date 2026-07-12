#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/private/tmp/LyricBarDMGBuild/Build/Products/Release/LyricBar.app"
OUTPUT_DMG="$ROOT_DIR/LyricBar-1.0.dmg"
WORK_DIR="$(mktemp -d /private/tmp/LyricBarDMG.XXXXXX)"
STAGE_DIR="$WORK_DIR/stage"
RW_DMG="$WORK_DIR/LyricBar-rw.dmg"

xcodebuild \
    -project "$ROOT_DIR/LyricBar.xcodeproj" \
    -scheme LyricBar \
    -configuration Release \
    -derivedDataPath /private/tmp/LyricBarDMGBuild \
    CODE_SIGNING_ALLOWED=NO \
    build

mkdir -p "$STAGE_DIR/.background"
ditto "$APP_PATH" "$STAGE_DIR/LyricBar.app"
cp "$ROOT_DIR/DMG-Install.txt" "$STAGE_DIR/설치방법.txt"
ln -s /Applications "$STAGE_DIR/Applications"

swift -module-cache-path "$WORK_DIR/swift-module-cache" "$ROOT_DIR/scripts/make_dmg_background.swift" "$STAGE_DIR/.background/background.png"

hdiutil create \
    -volname LyricBar \
    -srcfolder "$STAGE_DIR" \
    -fs HFS+ \
    -format UDRW \
    -size 40m \
    "$RW_DMG"

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_DIR="$(printf "%s\n" "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { sub(/^.*Apple_HFS[[:space:]]+/, ""); print; exit }')"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    printf "%s\n" "$ATTACH_OUTPUT"
    echo "Failed to locate mounted DMG volume." >&2
    exit 1
fi

SetFile -a V "$MOUNT_DIR/.background"
osascript "$ROOT_DIR/scripts/style_dmg.applescript" "$MOUNT_DIR"
test -f "$MOUNT_DIR/.DS_Store"
bless --folder "$MOUNT_DIR" --openfolder "$MOUNT_DIR"
sync
hdiutil detach "$MOUNT_DIR"

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG" \
    -ov

hdiutil verify "$OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
