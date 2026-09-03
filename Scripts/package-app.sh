#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/build/OrcaBatteryGuardian.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MASCOT_PATH="$PROJECT_DIR/Sources/OrcaBatteryGuardian/Resources/orca-mascot.png"
TEMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"

trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$PROJECT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/OrcaBatteryGuardian_OrcaBatteryGuardian.bundle"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BIN_DIR/OrcaBatteryGuardian" "$MACOS_DIR/OrcaBatteryGuardian"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${specification%% *}"
    filename="${specification#* }"
    sips -z "$size" "$size" "$MASCOT_PATH" --out "$ICONSET_DIR/$filename" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
    rm -rf "$RESOURCES_DIR/OrcaBatteryGuardian_OrcaBatteryGuardian.bundle"
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
print "$APP_DIR"
