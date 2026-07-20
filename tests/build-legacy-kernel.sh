#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_REF="${KERNEL_REF:-v7.0}"
TEST_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

git clone --depth=1 --branch "$KERNEL_REF" \
    https://github.com/torvalds/linux.git "$TEST_DIR/linux"
make -C "$TEST_DIR/linux" defconfig
make -C "$TEST_DIR/linux" -j"$(nproc)" modules_prepare

git clone --depth=1 \
    https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git \
    "$TEST_DIR/wireless-next"
git -C "$TEST_DIR/wireless-next" apply "$ROOT_DIR/patches/legacy-action-frame-api.patch"

mt76_dir="$TEST_DIR/wireless-next/drivers/net/wireless/mediatek/mt76"
make -C "$TEST_DIR/linux" M="$mt76_dir" \
    CONFIG_MT76_CORE=m \
    CONFIG_MT76_CONNAC_LIB=m \
    CONFIG_MT792x_LIB=m \
    CONFIG_MT7925_COMMON=m \
    CONFIG_MT7925E=m \
    KBUILD_MODPOST_WARN=1 \
    modules -j"$(nproc)"

echo "wireless-next mt76 modules build against $KERNEL_REF headers."
