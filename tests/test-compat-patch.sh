#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$ROOT_DIR/patches/legacy-action-frame-api.patch"
SOURCE_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git/plain"
TEST_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

source_files=(
    "drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c"
    "drivers/net/wireless/mediatek/mt76/mt7925/mac.c"
    "drivers/net/wireless/mediatek/mt76/mt7925/mcu.c"
    "drivers/net/wireless/mediatek/mt76/mt7996/mac.c"
)

git init --quiet "$TEST_DIR"

for source_file in "${source_files[@]}"; do
    mkdir -p "$TEST_DIR/$(dirname "$source_file")"
    curl --fail --location --silent --show-error \
        "$SOURCE_BASE/$source_file?h=main" \
        --output "$TEST_DIR/$source_file"
done

git -C "$TEST_DIR" add .
git -C "$TEST_DIR" \
    -c user.name="Compatibility Test" \
    -c user.email="compat-test@example.invalid" \
    commit --quiet -m "Record wireless-next source"

git -C "$TEST_DIR" apply --check "$PATCH_FILE"
git -C "$TEST_DIR" apply "$PATCH_FILE"

grep -q 'IEEE80211_MIN_ACTION_SIZE + 1 + 1 + 2' \
    "$TEST_DIR/drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c"
grep -q 'mgmt->u.action.u.addba_req.action_code' \
    "$TEST_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mac.c"
grep -q 'IEEE80211_EML_CAP_EMLSR_PADDING_DELAY' \
    "$TEST_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c"
grep -q 'IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY' \
    "$TEST_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c"

git -C "$TEST_DIR" apply --reverse --check "$PATCH_FILE"
git -C "$TEST_DIR" apply --reverse "$PATCH_FILE"
git -C "$TEST_DIR" diff --exit-code

echo "Compatibility patch applies cleanly to wireless-next main."
