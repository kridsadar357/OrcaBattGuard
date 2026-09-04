#!/bin/zsh
set -euo pipefail

HELPER=/Library/PrivilegedHelperTools/dev.orca.batteryguardian.bclm-control
BCLM_COPY=/Library/PrivilegedHelperTools/dev.orca.batteryguardian.bclm
SUDOERS=/etc/sudoers.d/orca-battery-guardian-intel

if [[ -x "$HELPER" ]]; then
    /usr/bin/sudo "$HELPER" write 100
fi
/usr/bin/sudo /bin/rm -f "$SUDOERS" "$HELPER" "$BCLM_COPY"
print 'Removed the Intel controller and restored BCLM to 100%.'
