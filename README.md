# MT7925 WiFi Fix for Linux

> **Fix WiFi disconnects, slow speeds, and instability on MediaTek MT7925 (Filogic 360) WiFi 7 chips**

Having WiFi problems on your new laptop? Random disconnects? Slow speeds? Connection drops? This repo builds the latest mt76 driver from the wireless-next kernel tree to fix stability issues not yet in stable kernels.

## Symptoms This Fixes

- ❌ WiFi randomly disconnects
- ❌ Slow WiFi speeds
- ❌ WiFi won't connect after sleep/suspend
- ❌ Connection drops under load
- ❌ "No Wi-Fi adapter found" after kernel update
- ❌ High latency / ping spikes

## Supported Devices

| Device | Chip | Status |
|--------|------|--------|
| ASUS ROG Flow Z13 (2025) | MT7925 | ✅ Tested |
| ASUS ROG Zephyrus G14/G16 (2024+) | MT7925 | Should work |
| ASUS Zenbook / Vivobook (2024+) | MT7925 | Should work |
| Laptops with MediaTek RZ738 | MT7925 | Should work |
| Any device with MT7925 WiFi 7 | MT7925 | Should work |

**Have a different device?** Open an issue to add it to the list!

## Supported Distros

Works on any Linux distro with kernel 6.x+:
- Fedora 39+ ✅ (tested on Fedora 43)
- Ubuntu 24.04+
- Arch Linux
- openSUSE Tumbleweed
- Debian Testing/Unstable
- Pop!_OS
- Linux Mint

## Quick Start

```bash
# Clone this repo
git clone https://github.com/burakgon/mt7925-wifi-patches.git
cd mt7925-wifi-patches

# Install dependencies (pick your distro)
# Fedora:
sudo dnf install kernel-devel kernel-headers gcc make git

# Ubuntu/Debian:
sudo apt install linux-headers-$(uname -r) build-essential git

# Arch:
sudo pacman -S linux-headers base-devel git

# Run the rebuild script
sudo ./mt76-rebuild.sh
```

## After Kernel Updates

Rebuild the driver after each kernel update:

```bash
cd mt7925-wifi-patches
sudo ./mt76-rebuild.sh
```

## Desktop Notifications (Optional)

Get notified when patches need to be reapplied:

```bash
# Autostart on login (KDE/GNOME/XFCE)
mkdir -p ~/.config/autostart
cp mt76-check.desktop ~/.config/autostart/

# Add to app launcher
mkdir -p ~/.local/share/applications
cp mt76-status.desktop ~/.local/share/applications/
```

## How It Works

1. Downloads the `wireless-next` kernel tree (latest WiFi driver development)
2. Builds mt76 driver modules for your kernel
3. Replaces stock modules with patched versions
4. Backs up original modules for easy restore

## Verify It's Working

```bash
# Check modules are loaded
lsmod | grep mt79

# Check custom marker exists
ls /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/.custom-mt76
```

## Restore Stock Drivers

```bash
cd mt7925-wifi-patches
sudo cp -r ./backup-modules/* /lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt76/
sudo depmod -a
sudo reboot
```

## Troubleshooting

**Build fails with "kernel headers not found"**
```bash
# Fedora
sudo dnf install kernel-devel-$(uname -r)

# Ubuntu
sudo apt install linux-headers-$(uname -r)
```

**WiFi still not working after install**
- Reboot your system
- Check `dmesg | grep mt79` for errors
- Open an issue with your logs

## Related Links

- [wireless-next tree](https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git/)
- [OpenWrt mt76 driver](https://github.com/openwrt/mt76)
- [Linux Wireless](https://wireless.wiki.kernel.org/)

## Contributing

Found a fix? Have a different device working? PRs and issues welcome!

## License

MIT License. See [LICENSE](LICENSE) file.

---

**Keywords:** MT7925 Linux driver, MediaTek WiFi fix, Filogic 360 Linux, WiFi 7 Linux, mt76 driver, ASUS ROG WiFi fix, Linux WiFi disconnects, RZ738 Linux, WiFi not working Linux, kernel WiFi patch
