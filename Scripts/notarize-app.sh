#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
if (( $# != 1 )) || [[ "$1" == --help || "$1" == -h ]]; then
    print 'Usage: notarize-app.sh KEYCHAIN_PROFILE'
    print 'Submits the current Developer ID signed build to Apple; stores the receipt in build/notarization/.'
    [[ "${1:-}" == --help || "${1:-}" == -h ]] && exit 0
    exit 2
fi
PROFILE="$1"
APP_DIR="$PROJECT_DIR/build/OrcaBatteryGuardian.app"
REPORT_DIR="$PROJECT_DIR/build/notarization/$(date +%Y%m%d-%H%M%S)-$$"
ARCHIVE="$REPORT_DIR/OrcaBatteryGuardian.zip"
mkdir -p "$REPORT_DIR"

codesign --verify --deep --strict --test-requirement \
    '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' \
    "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE"
if ! xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" \
    --wait --timeout 20m --output-format plist > "$REPORT_DIR/submission.plist"; then
    print -u2 "Notarization did not complete. Inspect $REPORT_DIR/submission.plist and check the submission ID before resubmitting."
    exit 1
fi
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$REPORT_DIR/submission.plist")"
if [[ "$STATUS" != Accepted ]]; then
    print -u2 "Notarization status: $STATUS. Receipt: $REPORT_DIR/submission.plist"
    exit 1
fi

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"
# Recreate the distributed archive after stapling, not from the uploaded copy.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DISTRIBUTION="$PROJECT_DIR/build/OrcaBatteryGuardian-$VERSION-macOS.zip"
[[ ! -e "$DISTRIBUTION" ]] || mv "$DISTRIBUTION" "$REPORT_DIR/previous-distribution.zip"
ditto -c -k --keepParent "$APP_DIR" "$DISTRIBUTION"
shasum -a 256 "$DISTRIBUTION"
print "Notarized distribution: $DISTRIBUTION"
