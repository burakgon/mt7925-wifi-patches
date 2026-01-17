#!/bin/bash
# MT7925 WiFi Driver Rebuild Script
# Builds and installs custom mt76 modules from wireless-next

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER=$(uname -r)
KDIR="/lib/modules/$KVER/build"
SRC_DIR="$SCRIPT_DIR/wireless-next/drivers/net/wireless/mediatek/mt76"
MOD_DIR="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
BACKUP_DIR="$SCRIPT_DIR/backup-modules"

echo "MT7925 WiFi Driver Rebuild"
echo "=========================="
echo "Kernel: $KVER"
echo ""

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root privileges."
    exec sudo "$0" "$@"
fi

# Check for kernel headers
if [[ ! -d "$KDIR" ]]; then
    echo "ERROR: Kernel headers not found at $KDIR"
    echo "Install with: sudo dnf install kernel-devel kernel-headers"
    exit 1
fi

cd "$SCRIPT_DIR"

# Clone wireless-next if not present
if [[ ! -d "wireless-next" ]]; then
    echo "[1/6] Cloning wireless-next tree (this may take a while)..."
    git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git
else
    echo "[1/6] Updating wireless-next source..."
    git -C wireless-next pull --ff-only 2>/dev/null || echo "Already up to date or offline"
fi

# Backup original modules (first run only)
if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
    echo "[2/6] Backing up original modules..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$MOD_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
else
    echo "[2/6] Backup already exists, skipping..."
fi

# Build
echo "[3/6] Building modules..."
make -C "$KDIR" M="$SRC_DIR" clean 2>/dev/null || true
make -C "$KDIR" M="$SRC_DIR" \
    CONFIG_MT76_CORE=m \
    CONFIG_MT76_CONNAC_LIB=m \
    CONFIG_MT792x_LIB=m \
    CONFIG_MT7925_COMMON=m \
    CONFIG_MT7925E=m \
    modules -j$(nproc)

# Unload current modules
echo "[4/6] Unloading current modules..."
modprobe -r mt7925e 2>/dev/null || true
modprobe -r mt7925_common 2>/dev/null || true
modprobe -r mt792x_lib 2>/dev/null || true
modprobe -r mt76_connac_lib 2>/dev/null || true
modprobe -r mt76 2>/dev/null || true

# Install
echo "[5/6] Installing new modules..."
mkdir -p "$MOD_DIR/mt7925"
cp "$SRC_DIR/mt76.ko" "$MOD_DIR/"
cp "$SRC_DIR/mt76-connac-lib.ko" "$MOD_DIR/"
cp "$SRC_DIR/mt792x-lib.ko" "$MOD_DIR/"
cp "$SRC_DIR/mt7925/mt7925-common.ko" "$MOD_DIR/mt7925/"
cp "$SRC_DIR/mt7925/mt7925e.ko" "$MOD_DIR/mt7925/"

# Mark as custom
echo "$KVER - $(date)" > "$MOD_DIR/.custom-mt76"

# Disable ASPM for stability
MODPROBE_CONF="/etc/modprobe.d/mt7925.conf"
if [[ ! -f "$MODPROBE_CONF" ]]; then
    echo "options mt7925e disable_aspm=1" > "$MODPROBE_CONF"
    echo "Created $MODPROBE_CONF (ASPM disabled for stability)"
fi

# Disable WiFi power save for stability
POWERSAVE_SCRIPT="/etc/NetworkManager/dispatcher.d/99-mt7925-powersave-off"
if [[ ! -f "$POWERSAVE_SCRIPT" ]]; then
    cat > "$POWERSAVE_SCRIPT" << 'SCRIPT'
#!/bin/bash
# Disable power save for MT7925 WiFi
IFACE="$1"
ACTION="$2"
if [[ "$ACTION" == "up" ]] && iw dev "$IFACE" info 2>/dev/null | grep -q "type managed"; then
    iw dev "$IFACE" set power_save off 2>/dev/null
fi
SCRIPT
    chmod +x "$POWERSAVE_SCRIPT"
    echo "Created $POWERSAVE_SCRIPT (WiFi power save disabled)"
fi

depmod -a

# Load
echo "[6/6] Loading new modules..."
modprobe mt7925e

echo ""
echo "✓ Done! Custom mt76 modules installed for kernel $KVER"
echo ""
lsmod | grep mt79
