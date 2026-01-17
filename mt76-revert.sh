#!/bin/bash
# MT7925 WiFi Driver Revert Script
# Removes custom modules and restores original Fedora drivers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER=$(uname -r)
MOD_DIR="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
BACKUP_DIR="$SCRIPT_DIR/backup-modules"

echo "MT7925 WiFi Driver Revert"
echo "========================="
echo "Kernel: $KVER"
echo ""

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root privileges."
    exec sudo "$0" "$@"
fi

echo "This will:"
echo "  - Remove custom mt76 modules"
echo "  - Restore original Fedora modules (if backup exists)"
echo "  - Remove ASPM disable config"
echo "  - Remove power save disable script"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Unload current modules
echo "[1/5] Unloading current modules..."
modprobe -r mt7925e 2>/dev/null || true
modprobe -r mt7925_common 2>/dev/null || true
modprobe -r mt792x_lib 2>/dev/null || true
modprobe -r mt76_connac_lib 2>/dev/null || true
modprobe -r mt76 2>/dev/null || true

# Restore backup modules
echo "[2/5] Restoring original modules..."
if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    cp -r "$BACKUP_DIR"/* "$MOD_DIR/"
    echo "Restored from backup"
else
    echo "No backup found, reinstalling from package..."
    dnf reinstall -y kernel-modules-$(uname -r) 2>/dev/null || echo "Could not reinstall kernel-modules"
fi

# Remove custom marker
rm -f "$MOD_DIR/.custom-mt76"

# Remove ASPM config
echo "[3/5] Removing ASPM config..."
if [[ -f "/etc/modprobe.d/mt7925.conf" ]]; then
    rm -f "/etc/modprobe.d/mt7925.conf"
    echo "Removed /etc/modprobe.d/mt7925.conf"
else
    echo "Not found, skipping"
fi

# Remove power save script
echo "[4/5] Removing power save script..."
if [[ -f "/etc/NetworkManager/dispatcher.d/99-mt7925-powersave-off" ]]; then
    rm -f "/etc/NetworkManager/dispatcher.d/99-mt7925-powersave-off"
    echo "Removed power save dispatcher script"
else
    echo "Not found, skipping"
fi

# Reload modules
echo "[5/5] Loading original modules..."
depmod -a
modprobe mt7925e

echo ""
echo "✓ Done! Reverted to original Fedora mt76 modules"
echo ""
lsmod | grep mt79
