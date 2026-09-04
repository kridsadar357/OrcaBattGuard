#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION=release
IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
INSTALL=false

usage() {
    print 'Usage: package-app.sh [--identity NAME_OR_HASH] [--notary-profile PROFILE] [--install] [--debug]'
    print 'Defaults to Release, ad-hoc signed for local use. Distribution requires Developer ID and notarization.'
}

while (( $# )); do
    case "$1" in
        --identity|--notary-profile)
            (( $# >= 2 )) || { usage; exit 2; }
            if [[ "$1" == --identity ]]; then IDENTITY="$2"; else NOTARY_PROFILE="$2"; fi
            shift 2 ;;
        --install) INSTALL=true; shift ;;
        --debug) CONFIGURATION=debug; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

if [[ -n "$NOTARY_PROFILE" && ( -z "$IDENTITY" || "$CONFIGURATION" != release ) ]]; then
    print -u2 'Notarization requires a Release build and an explicit Developer ID identity.'
    exit 2
fi

APP_DIR="$PROJECT_DIR/build/OrcaBatteryGuardian.app"
TEMP_DIR="$(mktemp -d)"
STAGED_APP="$TEMP_DIR/OrcaBatteryGuardian.app"
CONTENTS_DIR="$STAGED_APP/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"
MASCOT_PATH="$PROJECT_DIR/Sources/OrcaBatteryGuardian/Resources/orca-mascot.png"
trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$PROJECT_DIR"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/OrcaBatteryGuardian_OrcaBatteryGuardian.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || { print -u2 'Required resource bundle is missing.'; exit 1; }

mkdir -p "$CONTENTS_DIR/MacOS" "$RESOURCES_DIR" "$ICONSET_DIR" "$PROJECT_DIR/build"
cp "$BIN_DIR/OrcaBatteryGuardian" "$CONTENTS_DIR/MacOS/OrcaBatteryGuardian"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$RESOURCE_BUNDLE" "$RESOURCES_DIR/OrcaBatteryGuardian_OrcaBatteryGuardian.bundle"

for specification in \
    '16 icon_16x16.png' '32 icon_16x16@2x.png' \
    '32 icon_32x32.png' '64 icon_32x32@2x.png' \
    '128 icon_128x128.png' '256 icon_128x128@2x.png' \
    '256 icon_256x256.png' '512 icon_256x256@2x.png' \
    '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
    size="${specification%% *}"
    filename="${specification#* }"
    sips -z "$size" "$size" "$MASCOT_PATH" --out "$ICONSET_DIR/$filename" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
plutil -lint "$CONTENTS_DIR/Info.plist"

if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$STAGED_APP"
    codesign --verify --strict --test-requirement \
        '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' \
        "$STAGED_APP"
else
    codesign --force --sign - "$STAGED_APP"
    print -u2 'LOCAL BUILD: ad-hoc signed, not suitable for public distribution.'
fi
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

if [[ -e "$APP_DIR" ]]; then
    mkdir -p "$PROJECT_DIR/build/Backups"
    BACKUP="$PROJECT_DIR/build/Backups/OrcaBatteryGuardian-$(date +%Y%m%d-%H%M%S)-$$.zip"
    ditto -c -k --keepParent "$APP_DIR" "$BACKUP"
    mv "$APP_DIR" "$TEMP_DIR/previous.app"
fi
if ! ditto "$STAGED_APP" "$APP_DIR"; then
    rm -rf "$APP_DIR"
    [[ ! -d "$TEMP_DIR/previous.app" ]] || mv "$TEMP_DIR/previous.app" "$APP_DIR"
    exit 1
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    "$PROJECT_DIR/Scripts/notarize-app.sh" "$NOTARY_PROFILE"
elif [[ -n "$IDENTITY" ]]; then
    print -u2 'Developer ID signed; NOT notarized. Run Scripts/notarize-app.sh before public distribution.'
fi
if $INSTALL; then "$PROJECT_DIR/Scripts/install-app.sh"; fi
print "$APP_DIR"
