#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_CLI="/Applications/OrcaBatteryGuardian.app/Contents/MacOS/orca-battery"
INSTALL_DIR="$HOME/.local/bin"
SYSTEM_INSTALL=false

usage() {
    print 'Usage: install-cli.sh [--system]'
    print 'Installs orca and the orca-battery compatibility alias to ~/.local/bin.'
    print 'Use --system for /usr/local/bin.'
}

while (( $# )); do
    case "$1" in
        --system) SYSTEM_INSTALL=true; INSTALL_DIR="/usr/local/bin"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

if [[ -x "$APP_CLI" ]]; then
    SOURCE="$APP_CLI"
else
    cd "$PROJECT_DIR"
    swift build -c release --product orca-battery
    BIN_DIR="$(swift build -c release --show-bin-path)"
    SOURCE="$BIN_DIR/orca-battery"
fi

if $SYSTEM_INSTALL; then
    sudo install -m 755 "$SOURCE" "$INSTALL_DIR/orca"
    sudo ln -sfn orca "$INSTALL_DIR/orca-battery"
else
    mkdir -p "$INSTALL_DIR"
    install -m 755 "$SOURCE" "$INSTALL_DIR/orca"
    ln -sfn orca "$INSTALL_DIR/orca-battery"
fi

print "Installed $INSTALL_DIR/orca"
print "Alias: $INSTALL_DIR/orca-battery -> orca"
"$INSTALL_DIR/orca" version

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    print -u2 "Add $INSTALL_DIR to PATH before running orca by name."
fi
