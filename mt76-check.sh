#!/bin/bash
# MT7925 WiFi Patch Status Checker

KVER=$(uname -r)
MARKER="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76"
MODPROBE_CONF="/etc/modprobe.d/mt7925.conf"
WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/ && !/p2p/{print $2; exit}')

# Check ASPM status
if [[ -f "$MODPROBE_CONF" ]] && grep -q "disable_aspm=1" "$MODPROBE_CONF" 2>/dev/null; then
    ASPM_STATUS="✓ ASPM: Disabled"
else
    ASPM_STATUS="✗ ASPM: Enabled (may cause issues)"
fi

# Check power save status
if [[ -n "$WIFI_IFACE" ]]; then
    PS_STATE=$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | awk '{print $3}')
    if [[ "$PS_STATE" == "off" ]]; then
        PS_STATUS="✓ Power Save: Off"
    else
        PS_STATUS="✗ Power Save: On (may cause issues)"
    fi
else
    PS_STATUS="? Power Save: Unknown"
fi

if [[ -f "$MARKER" ]]; then
    STATUS="✓ All Good"
    URGENCY="normal"
    MSG="✓ Driver: Patched
$ASPM_STATUS
$PS_STATUS

Kernel: $KVER"
else
    STATUS="✗ Action Needed"
    URGENCY="critical"
    MSG="✗ Driver: Not Patched
$ASPM_STATUS
$PS_STATUS

Kernel: $KVER
Run: sudo ./mt76-rebuild.sh"
fi

notify-send -u "$URGENCY" -t 10000 "MT7925 WiFi: $STATUS" "$MSG"
