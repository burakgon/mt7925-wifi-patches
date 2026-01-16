#!/bin/bash
# MT7925 WiFi Patch Status Checker

KVER=$(uname -r)
MARKER="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76"

if [[ -f "$MARKER" ]]; then
    STATUS="✓ PATCHED"
    URGENCY="normal"
    MSG="Custom mt76 modules installed for kernel $KVER.

WiFi stability patches are active."
else
    STATUS="✗ NOT PATCHED"
    URGENCY="critical"
    MSG="Custom mt76 modules NOT installed for kernel $KVER.

Rebuild with: sudo ./mt76-rebuild.sh"
fi

notify-send -u "$URGENCY" "MT7925 WiFi: $STATUS" "$MSG"
