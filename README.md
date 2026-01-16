# MT7925 WiFi Stability Patches for Linux

Fixes WiFi stability issues on the **MediaTek MT7925** (Filogic 360) WiFi 7 chip by building the latest mt76 driver from the wireless-next kernel tree.

## Tested On

| Hardware | OS | Kernel | Status |
|----------|-----|--------|--------|
| ASUS ROG Flow Z13 (2025) | Fedora 43 | 6.18.5 | ✅ Working |

## The Problem

The MT7925 WiFi chip has stability issues with stock kernel drivers - random disconnects, slow speeds, or connection drops. The wireless-next tree contains fixes not yet merged into stable kernels.

## Quick Start

```bash
# Clone this repo
git clone https://github.com/burakgon/mt7925-wifi-patches.git
cd mt7925-wifi-patches

# Run the rebuild script (downloads sources on first run)
sudo ./mt76-rebuild.sh
```

## After Kernel Updates

When you update your kernel, rebuild the driver:

```bash
cd /path/to/mt7925-wifi-patches
sudo ./mt76-rebuild.sh
```

## Desktop Notifications

A notification system alerts you when patches need to be reapplied after a kernel update.

**Setup autostart notification:**
```bash
mkdir -p ~/.config/autostart
cp mt76-check.desktop ~/.config/autostart/
```

**Add app launcher entry:**
```bash
mkdir -p ~/.local/share/applications
cp mt76-status.desktop ~/.local/share/applications/
```

## Files

| File | Description |
|------|-------------|
| `mt76-rebuild.sh` | One-command rebuild and install script |
| `mt76-check.sh` | Notification script for patch status |
| `CLAUDE.md` | Instructions for Claude Code AI assistant |

## How It Works

1. Clones the `wireless-next` kernel tree (latest WiFi driver development)
2. Builds the mt76 driver modules against your current kernel
3. Replaces stock kernel modules with patched versions
4. Creates a marker file to track installation status

## Verifying Installation

```bash
# Check if custom modules are loaded
lsmod | grep mt79

# Check for custom marker
ls /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76
```

## Restoring Stock Drivers

```bash
# Backup modules are saved during first install
cd /path/to/mt7925-wifi-patches
sudo cp -r ./backup-modules/* \
    /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/
sudo depmod -a
sudo reboot
```

## Related Links

- [wireless-next tree](https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git/)
- [OpenWrt mt76 driver](https://github.com/openwrt/mt76)
- [MT7925 on WikiDevi](https://wikidevi.wi-cat.ru/MediaTek_MT7925)

## License

Scripts in this repository are released under MIT License. The mt76 driver is licensed under BSD-3-Clause-Clear.

## Contributing

Found a fix or improvement? PRs welcome!
