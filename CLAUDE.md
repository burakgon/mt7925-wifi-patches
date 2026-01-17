# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This project builds and installs custom mt76 WiFi drivers from the wireless-next kernel tree for the MediaTek MT7925 chip. The stock Fedora kernel drivers have stability issues.

## Rebuild After Kernel Update

When the user gets a kernel update and needs to rebuild the driver:

```bash
sudo ./mt76-rebuild.sh
```

That's it. The script handles everything: pulling updates, building, unloading old modules, installing new ones, and loading them.

## Manual Steps (if rebuild script fails)

1. **Update source:**
   ```bash
   git -C wireless-next pull
   ```

2. **Build:**
   ```bash
   KVER=$(uname -r)
   SRC_DIR=$(pwd)/wireless-next/drivers/net/wireless/mediatek/mt76
   make -C /lib/modules/$KVER/build M=$SRC_DIR clean
   make -C /lib/modules/$KVER/build M=$SRC_DIR \
       CONFIG_MT76_CORE=m \
       CONFIG_MT76_CONNAC_LIB=m \
       CONFIG_MT792x_LIB=m \
       CONFIG_MT7925_COMMON=m \
       CONFIG_MT7925E=m \
       modules
   ```

3. **Install:**
   ```bash
   sudo modprobe -r mt7925e mt7925_common mt792x_lib mt76_connac_lib mt76

   MOD_DIR=/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76
   sudo cp $SRC_DIR/mt76.ko $MOD_DIR/
   sudo cp $SRC_DIR/mt76-connac-lib.ko $MOD_DIR/
   sudo cp $SRC_DIR/mt792x-lib.ko $MOD_DIR/
   sudo cp $SRC_DIR/mt7925/mt7925-common.ko $MOD_DIR/mt7925/
   sudo cp $SRC_DIR/mt7925/mt7925e.ko $MOD_DIR/mt7925/
   sudo touch $MOD_DIR/.custom-mt76

   sudo depmod -a
   sudo modprobe mt7925e
   ```

## Revert to Original Drivers

To undo all changes and restore original Fedora drivers:

```bash
sudo ./mt76-revert.sh
```

This removes custom modules, ASPM config, power save script, and restores original drivers.

## Key Files

- `mt76-rebuild.sh` - One-command rebuild and install
- `mt76-revert.sh` - Undo all changes, restore original drivers
- `mt76-check.sh` - Shows notification with patch status
- `wireless-next/` - Kernel source tree with mt76 driver (auto-downloaded)
- `backup-modules/` - Backup of original Fedora modules

## Stability Settings

The rebuild script automatically configures these for stability:

**ASPM Disabled** (`/etc/modprobe.d/mt7925.conf`):
- Disables PCIe Active State Power Management
- Prevents random disconnects and freezes

**Power Save Disabled** (`/etc/NetworkManager/dispatcher.d/99-mt7925-powersave-off`):
- Disables WiFi power save when interface comes up
- Prevents latency spikes and connection drops

## Hardware

- Chip: MediaTek MT7925 (Filogic 360, WiFi 7)
- Interface: PCIe (`mt7925e`)
- Firmware: `/lib/firmware/mediatek/mt7925/`

## Check for New OpenWrt Patches

OpenWrt may have additional MT7925 fixes not yet in wireless-next. Check and apply if needed:

1. **Check OpenWrt mt76 commits:**
   ```bash
   # Clone or update OpenWrt mt76 repo
   if [[ -d openwrt-mt76 ]]; then
       git -C openwrt-mt76 pull
   else
       git clone https://github.com/openwrt/mt76.git openwrt-mt76
   fi

   # Show recent MT7925-specific commits
   git -C openwrt-mt76 log --oneline --grep="mt7925" -20
   git -C openwrt-mt76 log --oneline -- mt7925/ | head -20
   ```

2. **Compare with wireless-next:**
   ```bash
   # Check wireless-next MT7925 commits
   git -C wireless-next log --oneline -- drivers/net/wireless/mediatek/mt76/mt7925/ | head -20
   ```

3. **If OpenWrt has newer fixes**, check if they can be cherry-picked or manually applied to wireless-next source.

**OpenWrt URLs:**
- MT76 repo: https://github.com/openwrt/mt76
- MT76 patches: https://github.com/openwrt/openwrt/tree/main/package/kernel/mt76/patches

**Note:** OpenWrt's mt76 driver has diverged from mainline and may not compile directly against stock kernels. Cherry-pick specific commits or manually port fixes if needed.

## Notification System

Desktop notifications alert the user about patch status.

**How it works:**
- On login/reboot: `~/.config/autostart/mt76-check.desktop` runs `mt76-check.sh`
- App launcher: "WiFi Patch Status" app also runs `mt76-check.sh`
- The script checks if `/lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76` marker file exists
- Shows "✓ PATCHED" or "✗ NOT PATCHED" notification

**Files:**
- `mt76-check.sh` - Notification script
- `~/.config/autostart/mt76-check.desktop` - Autostart entry (runs on login)
- `~/.local/share/applications/mt76-status.desktop` - App launcher entry

**To update notification text**, edit `mt76-check.sh`.

**To disable autostart notification:**
```bash
rm ~/.config/autostart/mt76-check.desktop
```

**To remove app launcher entry:**
```bash
rm ~/.local/share/applications/mt76-status.desktop
```

## Checking Status

```bash
# Check if custom modules are loaded
lsmod | grep mt79

# Check module info
modinfo mt76 | head -10

# Check if custom marker exists
ls -la /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76

# Manually trigger notification
./mt76-check.sh
```
