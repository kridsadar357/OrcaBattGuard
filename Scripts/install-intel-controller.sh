#!/bin/zsh
set -euo pipefail

HELPER_DIR=/Library/PrivilegedHelperTools
HELPER="$HELPER_DIR/dev.orca.batteryguardian.bclm-control"
BCLM_COPY="$HELPER_DIR/dev.orca.batteryguardian.bclm"
SUDOERS=/etc/sudoers.d/orca-battery-guardian-intel

if [[ "$(uname -m)" != x86_64 ]]; then
    print -u2 'This installer is only for Intel x86_64 Macs.'
    exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MACOS_MAJOR < 13 || MACOS_MAJOR > 14 )); then
    print -u2 'Intel charge control is supported only on macOS 13 and 14.'
    print -u2 'macOS 15 or newer blocks BCLM writes unless SIP is disabled; Orca will not request that.'
    exit 1
fi

BCLM_SOURCE="$(command -v bclm || true)"
if [[ -z "$BCLM_SOURCE" || ! -x "$BCLM_SOURCE" ]]; then
    print -u2 'bclm is required. Install it first:'
    print -u2 '  brew tap zackelia/formulae'
    print -u2 '  brew install bclm'
    exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/controller" <<'SCRIPT'
#!/bin/sh
set -eu
BCLM=/Library/PrivilegedHelperTools/dev.orca.batteryguardian.bclm

case "${1-}" in
    read)
        [ "$#" -eq 1 ] || exit 64
        exec "$BCLM" read
        ;;
    write)
        [ "$#" -eq 2 ] || exit 64
        case "$2" in *[!0-9]*|'') exit 64 ;; esac
        [ "$2" -ge 50 ] && [ "$2" -le 100 ] || exit 64
        [ "$(id -u)" -eq 0 ] || exit 77
        exec "$BCLM" write "$2"
        ;;
    *) exit 64 ;;
esac
SCRIPT

cat > "$TEMP_DIR/sudoers" <<SUDOERS
%admin ALL=(root) NOPASSWD: $HELPER write *
SUDOERS

/usr/bin/sudo /usr/sbin/visudo -cf "$TEMP_DIR/sudoers"
/usr/bin/sudo /usr/bin/install -d -o root -g wheel -m 755 "$HELPER_DIR"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 755 "$BCLM_SOURCE" "$BCLM_COPY"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 755 "$TEMP_DIR/controller" "$HELPER"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 440 "$TEMP_DIR/sudoers" "$SUDOERS"
/usr/bin/sudo /usr/sbin/visudo -cf "$SUDOERS"

CURRENT="$($HELPER read)"
case "$CURRENT" in *[!0-9]*|'') print -u2 "Invalid BCLM readback: $CURRENT"; exit 1 ;; esac
(( CURRENT >= 50 && CURRENT <= 100 )) || { print -u2 "Invalid BCLM readback: $CURRENT"; exit 1; }
print "Installed Intel controller. Current BCLM limit: $CURRENT%"
print 'Open Orca Battery Guardian and run Diagnostics.'
