#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/build/OrcaBatteryGuardian.app"
DESTINATION=/Applications/OrcaBatteryGuardian.app
BUNDLE_ID=dev.orca.batteryguardian
if (( $# )); then
    print 'Usage: install-app.sh (installs the packaged app in /Applications and opens it)'
    [[ "$1" == --help || "$1" == -h ]] && exit 0
    exit 2
fi
[[ -w /Applications ]] || { print -u2 '/Applications is not writable. Install using Finder with administrator approval.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" == "$BUNDLE_ID" ]]
codesign --verify --deep --strict "$SOURCE"

STAGING="$(mktemp -d /Applications/.OrcaInstall.XXXXXX)"
cleanup() {
    if [[ -d "$STAGING/previous.app" && ! -e "$DESTINATION" ]]; then
        mv "$STAGING/previous.app" "$DESTINATION"
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
ditto "$SOURCE" "$STAGING/OrcaBatteryGuardian.app"
codesign --verify --deep --strict "$STAGING/OrcaBatteryGuardian.app"

osascript \
    -e 'with timeout of 20 seconds' \
    -e 'if application id "dev.orca.batteryguardian" is running then tell application id "dev.orca.batteryguardian" to quit' \
    -e 'repeat 60 times' \
    -e 'if not (application id "dev.orca.batteryguardian" is running) then return' \
    -e 'delay 0.25' \
    -e 'end repeat' \
    -e 'error "Orca is still running. Installation was cancelled without replacing it."' \
    -e 'end timeout'
if [[ -e "$DESTINATION" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")" == "$BUNDLE_ID" ]] || {
        print -u2 'Destination belongs to a different app; refusing to replace it.'; exit 1;
    }
    mkdir -p "$PROJECT_DIR/build/Backups"
    ditto -c -k --keepParent "$DESTINATION" "$PROJECT_DIR/build/Backups/Installed-OrcaBatteryGuardian-$(date +%Y%m%d-%H%M%S)-$$.zip"
    mv "$DESTINATION" "$STAGING/previous.app"
fi
mv "$STAGING/OrcaBatteryGuardian.app" "$DESTINATION"
if ! codesign --verify --deep --strict "$DESTINATION"; then
    mv "$DESTINATION" "$STAGING/failed.app"
    exit 1
fi
open "$DESTINATION"
print "Installed and opened: $DESTINATION"
