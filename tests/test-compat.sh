#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPAT="$ROOT_DIR/scripts/compat.sh"
BUILD_LEGACY="$ROOT_DIR/tests/build-legacy-kernel.sh"
ACTION_PATCH="$ROOT_DIR/patches/legacy-action-frame-api.patch"
EML_PATCH="$ROOT_DIR/patches/legacy-eml-api.patch"
ALLOC_FLEX_PATCH="$ROOT_DIR/patches/legacy-alloc-flex-api.patch"
RX_LINK_STA_PATCH="$ROOT_DIR/patches/legacy-rx-link-sta-api.patch"
WIRELESS_NEXT_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git"
WIRELESS_NEXT_PLAIN="https://git.kernel.org/pub/scm/linux/kernel/git/wireless/wireless-next.git/plain"
TEST_DIR="$(mktemp -d)"
SOURCE_DIR="$TEST_DIR/wireless-next"
WIRELESS_NEXT_SHA=''

RX_LIST_LEGACY_API='void ieee80211_rx_list(struct ieee80211_hw *hw, struct ieee80211_sta *sta,
struct sk_buff *skb, struct list_head *list);'

RX_LIST_CURRENT_API='void ieee80211_rx_list(struct ieee80211_hw *hw,
struct ieee80211_link_sta *link_sta,
struct sk_buff *skb, struct list_head *list);'

NAN_UAPI_CONTRACT='NL80211_IFTYPE_NAN,
NL80211_IFTYPE_NAN_DATA,
NL80211_EXT_FEATURE_SECURE_NAN,'

NAN_IEEE80211_CONTRACT='#define NAN_OP_MODE_PHY_MODE_MASK
#define NAN_DEV_CAPA_EXT_KEY_ID_SUPPORTED'

NAN_CFG80211_CONTRACT='struct cfg80211_nan_band_config {
struct ieee80211_channel *chan;
s8 rssi_close;
s8 rssi_middle;
u8 awake_dw_interval;
};
struct cfg80211_nan_conf {
u8 master_pref;
u8 bands;
u8 cluster_id[ETH_ALEN];
u16 scan_period;
u16 scan_dwell_time;
u8 discovery_beacon_interval;
bool enable_dw_notification;
struct cfg80211_nan_band_config band_cfgs[NUM_NL80211_BANDS];
};
#define CFG80211_NAN_SCHED_NUM_TIME_SLOTS
#define CFG80211_NAN_MAX_PEER_MAPS
#define CFG80211_NAN_INVALID_MAP_ID
WIPHY_NAN_FLAGS_CONFIGURABLE_SYNC =
WIPHY_NAN_FLAGS_USERSPACE_DE =
struct wiphy_nan_capa {
u32 flags;
u8 op_mode;
u8 n_antennas;
u16 max_channel_switch_time;
u8 dev_capabilities;
struct ieee80211_sta_ht_cap ht;
struct ieee80211_sta_vht_cap vht;
struct ieee80211_sta_he_cap he;
} phy;
};
struct wiphy {
u8 nan_supported_bands;
struct wiphy_nan_capa nan_capa;
};
void cfg80211_next_nan_dw_notif('

NAN_MAC80211_CONTRACT='BSS_CHANGED_NAN_LOCAL_SCHED
struct ieee80211_nan_channel {
struct ieee80211_chanctx_conf *chanctx_conf;
u8 channel_entry[6];
};
struct ieee80211_nan_peer_map {
u8 map_id;
struct ieee80211_nan_channel *slots[CFG80211_NAN_SCHED_NUM_TIME_SLOTS];
};
struct ieee80211_nan_peer_sched {
u16 max_chan_switch;
struct ieee80211_nan_peer_map maps[CFG80211_NAN_MAX_PEER_MAPS];
u8 n_channels;
struct ieee80211_nan_channel channels[];
};
struct ieee80211_nan_sched_cfg {
struct ieee80211_nan_channel *schedule[CFG80211_NAN_SCHED_NUM_TIME_SLOTS];
u8 avail_blob[IEEE80211_NAN_AVAIL_BLOB_MAX_LEN];
u16 avail_blob_len;
bool deferred;
};
struct ieee80211_vif_cfg {
struct ieee80211_nan_sched_cfg nan_sched;
};
struct ieee80211_vif {
struct ieee80211_vif_cfg cfg;
};
struct ieee80211_sta {
struct ieee80211_sta __rcu *nmi;
struct ieee80211_nan_peer_sched *nan_sched;
};
struct ieee80211_ops {
int (*start_nan)(
int (*stop_nan)(
int (*nan_change_conf)(
int (*nan_peer_sched_changed)(
};
struct wireless_dev *ieee80211_vif_to_wdev(
void ieee80211_nan_sched_update_done(
void ieee80211_nan_cluster_joined(
bool ieee80211_vif_nan_started('

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local generation=$1
    local rx_api=${2-auto}
    local kdir="$TEST_DIR/$generation"
    local action_macro eml_symbols alloc_flex nan_uapi nan_ieee80211 cfg_nan mac_nan
    local aql_decl aql_export rx_list_decl

    nan_uapi=''
    nan_ieee80211=''
    cfg_nan=''
    mac_nan=''
    aql_decl=''
    aql_export=''
    alloc_flex='#define kzalloc_flex(P, FAM, COUNT, ...)'

    case "$generation" in
        v6.18|v7.0)
            action_macro='#define IEEE80211_MIN_ACTION_SIZE 24'
            eml_symbols=$'#define IEEE80211_EML_CAP_EMLSR_PADDING_DELAY 0\n#define IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY 0'
            [[ $generation == v6.18 ]] && alloc_flex=''
            ;;
        v7.1)
            action_macro='#define IEEE80211_MIN_ACTION_SIZE(member) 24'
            eml_symbols=$'#define IEEE80211_EML_CAP_EMLSR_PADDING_DELAY 0\n#define IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY 0'
            nan_uapi=$NAN_UAPI_CONTRACT
            nan_ieee80211=$NAN_IEEE80211_CONTRACT
            cfg_nan=$NAN_CFG80211_CONTRACT
            mac_nan=${NAN_MAC80211_CONTRACT/ieee80211_nan_cluster_joined/missing_nan_cluster_joined}
            ;;
        v7.2)
            action_macro='#define IEEE80211_MIN_ACTION_SIZE(member) 24'
            eml_symbols=$'#define IEEE80211_EML_CAP_EML_PADDING_DELAY 0\n#define IEEE80211_EML_CAP_EML_TRANSITION_DELAY 0'
            nan_uapi=$NAN_UAPI_CONTRACT
            nan_ieee80211=$NAN_IEEE80211_CONTRACT
            cfg_nan=$NAN_CFG80211_CONTRACT
            mac_nan=$NAN_MAC80211_CONTRACT
            aql_decl='void ieee80211_txq_aql_pending(void);'
            ;;
        current)
            action_macro='#define IEEE80211_MIN_ACTION_SIZE(member) 24'
            eml_symbols=$'#define IEEE80211_EML_CAP_EML_PADDING_DELAY 0\n#define IEEE80211_EML_CAP_EML_TRANSITION_DELAY 0'
            nan_uapi=$NAN_UAPI_CONTRACT
            nan_ieee80211=$NAN_IEEE80211_CONTRACT
            cfg_nan=$NAN_CFG80211_CONTRACT
            mac_nan=$NAN_MAC80211_CONTRACT
            aql_decl='void ieee80211_txq_aql_pending(void);'
            aql_export='0x0 ieee80211_txq_aql_pending mac80211 EXPORT_SYMBOL_GPL'
            ;;
        *)
            fail "unknown fixture generation: $generation"
            ;;
    esac

    if [[ $rx_api == auto ]]; then
        if [[ $generation == current ]]; then
            rx_api=current
        else
            rx_api=legacy
        fi
    fi
    case "$rx_api" in
        legacy)
            rx_list_decl=$RX_LIST_LEGACY_API
            ;;
        current)
            rx_list_decl=$RX_LIST_CURRENT_API
            ;;
        *)
            fail "unknown RX API fixture: $rx_api"
            ;;
    esac

    rm -rf "$kdir"
    mkdir -p "$kdir/include/linux" "$kdir/include/net" "$kdir/include/uapi/linux"
    printf '%s\n' "$action_macro" > "$kdir/include/linux/ieee80211.h"
    if [[ $generation == v6.18 ]]; then
        printf '%s\n' "$eml_symbols" >> "$kdir/include/linux/ieee80211.h"
    else
        printf '%s\n' "$eml_symbols" > "$kdir/include/linux/ieee80211-eht.h"
    fi
    printf '%s\n' "$nan_ieee80211" > "$kdir/include/linux/ieee80211-nan.h"
    printf '%s\n' "$nan_uapi" > "$kdir/include/uapi/linux/nl80211.h"
    printf '%s\n' "$cfg_nan" > "$kdir/include/net/cfg80211.h"
    printf '%s\n' "$mac_nan" "$aql_decl" "$rx_list_decl" > "$kdir/include/net/mac80211.h"
    printf '%s\n' "$alloc_flex" > "$kdir/include/linux/slab.h"
    printf '%s\n' "$aql_export" > "$kdir/Module.symvers"
    printf '%s\n' "$kdir"
}

assert_patches() {
    local generation=$1
    local expected=$2
    local kdir actual

    kdir=$(make_fixture "$generation")
    actual=$("$COMPAT" detect "$kdir")
    [[ $actual == "$expected" ]] ||
        fail "$generation: expected $(printf '%q' "$expected"), got $(printf '%q' "$actual")"
}

assert_nan_contract_fail_closed() {
    local entry header token kdir file line actual found
    local -a contract=(
        'include/uapi/linux/nl80211.h|NL80211_IFTYPE_NAN,'
        'include/uapi/linux/nl80211.h|NL80211_EXT_FEATURE_SECURE_NAN,'
        'include/linux/ieee80211-nan.h|#define NAN_OP_MODE_PHY_MODE_MASK'
        'include/linux/ieee80211-nan.h|#define NAN_DEV_CAPA_EXT_KEY_ID_SUPPORTED'
        'include/net/cfg80211.h|struct cfg80211_nan_band_config {'
        'include/net/cfg80211.h|struct ieee80211_channel *chan;'
        'include/net/cfg80211.h|s8 rssi_close;'
        'include/net/cfg80211.h|s8 rssi_middle;'
        'include/net/cfg80211.h|u8 awake_dw_interval;'
        'include/net/cfg80211.h|struct cfg80211_nan_conf {'
        'include/net/cfg80211.h|u8 master_pref;'
        'include/net/cfg80211.h|u8 bands;'
        'include/net/cfg80211.h|u8 cluster_id[ETH_ALEN];'
        'include/net/cfg80211.h|u16 scan_period;'
        'include/net/cfg80211.h|u16 scan_dwell_time;'
        'include/net/cfg80211.h|u8 discovery_beacon_interval;'
        'include/net/cfg80211.h|bool enable_dw_notification;'
        'include/net/cfg80211.h|struct cfg80211_nan_band_config band_cfgs[NUM_NL80211_BANDS];'
        'include/net/cfg80211.h|#define CFG80211_NAN_INVALID_MAP_ID'
        'include/net/cfg80211.h|WIPHY_NAN_FLAGS_CONFIGURABLE_SYNC ='
        'include/net/cfg80211.h|WIPHY_NAN_FLAGS_USERSPACE_DE ='
        'include/net/cfg80211.h|struct wiphy_nan_capa {'
        'include/net/cfg80211.h|u32 flags;'
        'include/net/cfg80211.h|u8 op_mode;'
        'include/net/cfg80211.h|u8 n_antennas;'
        'include/net/cfg80211.h|u16 max_channel_switch_time;'
        'include/net/cfg80211.h|u8 dev_capabilities;'
        'include/net/cfg80211.h|struct ieee80211_sta_ht_cap ht;'
        'include/net/cfg80211.h|struct ieee80211_sta_vht_cap vht;'
        'include/net/cfg80211.h|struct ieee80211_sta_he_cap he;'
        'include/net/cfg80211.h|} phy;'
        'include/net/cfg80211.h|u8 nan_supported_bands;'
        'include/net/cfg80211.h|struct wiphy_nan_capa nan_capa;'
        'include/net/cfg80211.h|void cfg80211_next_nan_dw_notif('
        'include/net/mac80211.h|struct ieee80211_nan_channel {'
        'include/net/mac80211.h|struct ieee80211_chanctx_conf *chanctx_conf;'
        'include/net/mac80211.h|u8 channel_entry[6];'
        'include/net/mac80211.h|struct ieee80211_nan_peer_map {'
        'include/net/mac80211.h|u8 map_id;'
        'include/net/mac80211.h|struct ieee80211_nan_channel *slots[CFG80211_NAN_SCHED_NUM_TIME_SLOTS];'
        'include/net/mac80211.h|struct ieee80211_nan_peer_sched {'
        'include/net/mac80211.h|u16 max_chan_switch;'
        'include/net/mac80211.h|struct ieee80211_nan_peer_map maps[CFG80211_NAN_MAX_PEER_MAPS];'
        'include/net/mac80211.h|u8 n_channels;'
        'include/net/mac80211.h|struct ieee80211_nan_channel channels[];'
        'include/net/mac80211.h|struct ieee80211_nan_sched_cfg {'
        'include/net/mac80211.h|struct ieee80211_nan_channel *schedule[CFG80211_NAN_SCHED_NUM_TIME_SLOTS];'
        'include/net/mac80211.h|u8 avail_blob[IEEE80211_NAN_AVAIL_BLOB_MAX_LEN];'
        'include/net/mac80211.h|u16 avail_blob_len;'
        'include/net/mac80211.h|bool deferred;'
        'include/net/mac80211.h|struct ieee80211_nan_sched_cfg nan_sched;'
        'include/net/mac80211.h|struct ieee80211_vif_cfg cfg;'
        'include/net/mac80211.h|struct ieee80211_sta __rcu *nmi;'
        'include/net/mac80211.h|struct ieee80211_nan_peer_sched *nan_sched;'
        'include/net/mac80211.h|int (*start_nan)('
        'include/net/mac80211.h|int (*stop_nan)('
        'include/net/mac80211.h|int (*nan_change_conf)('
        'include/net/mac80211.h|struct wireless_dev *ieee80211_vif_to_wdev('
        'include/net/mac80211.h|bool ieee80211_vif_nan_started('
    )

    for entry in "${contract[@]}"; do
        IFS='|' read -r header token <<< "$entry"
        kdir=$(make_fixture current)
        file="$kdir/$header"
        found=0
        while IFS= read -r line; do
            if [[ $line == "$token" ]]; then
                found=1
                continue
            fi
            printf '%s\n' "$line"
        done < "$file" > "$file.mutated"
        ((found)) || fail "missing NAN fixture token: $token"
        mv "$file.mutated" "$file"

        actual=$("$COMPAT" detect "$kdir")
        [[ $actual == nan ]] ||
            fail "missing NAN contract $token: expected nan, got $(printf '%q' "$actual")"
    done
}

assert_kbuild_tool_args() {
    local kdir fake_bin make_log git_log output line expected calls=0
    local kbuild_dir mt76_dir previous
    local -a expected_args=(
        LLVM=1
        LLVM_IAS=0
        CC=clang-test
        LD=ld.lld-test
        AR=llvm-ar-test
        NM=llvm-nm-test
        STRIP=llvm-strip-test
        OBJCOPY=llvm-objcopy-test
        OBJDUMP=llvm-objdump-test
        READELF=llvm-readelf-test
        HOSTCC=host-clang-test
        HOSTCXX=host-clangxx-test
    )

    kdir=$(make_fixture current)
    fake_bin="$TEST_DIR/fake-build-bin"
    make_log="$TEST_DIR/fake-make.log"
    git_log="$TEST_DIR/fake-build-git.log"
    output="$TEST_DIR/fake-build.stdout"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$FAKE_GIT_LOG"

case " $* " in
    *' clone '*)
        destination=${!#}
        mkdir -p "$destination"
        cp -R "$FAKE_KDIR_FIXTURE/." "$destination/"
        ;;
    *' init '*)
        destination=${!#}
        mkdir -p "$destination"
        cp -R "$FAKE_KDIR_FIXTURE/." "$destination/"
        ;;
    *' rev-parse --is-inside-work-tree '*)
        printf '%s\n' true
        ;;
    *' rev-parse HEAD '*)
        printf '%s\n' ca800a9302764c445de0da0e84d2252400a770ee
        ;;
esac
EOF
    cat > "$fake_bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s ' "$@" >> "$FAKE_MAKE_LOG"
printf '\n' >> "$FAKE_MAKE_LOG"
mt76_dir=''
kdir=''
previous=''
for arg in "$@"; do
    if [[ $previous == -C ]]; then
        kdir=$arg
    fi
    case $arg in
        M=*) mt76_dir=${arg#M=} ;;
    esac
    previous=$arg
done
if [[ " $* " == *' modules '* && -n $mt76_dir ]]; then
    if [[ ${FAKE_REQUIRE_SYMVERS_FORMAT-0} == 1 ]]; then
        expected=$'0x00000000\tieee80211_txq_aql_pending\tmac80211\tEXPORT_SYMBOL_GPL\t'
        [[ $(<"$kdir/Module.symvers") == "$expected" ]] || {
            printf 'invalid synthetic Module.symvers format\n' >&2
            exit 1
        }
    fi
    mkdir -p "$mt76_dir/mt7925"
    for module in \
        "$mt76_dir/mt76.ko" \
        "$mt76_dir/mt76-connac-lib.ko" \
        "$mt76_dir/mt792x-lib.ko" \
        "$mt76_dir/mt7925/mt7925-common.ko" \
        "$mt76_dir/mt7925/mt7925e.ko"; do
        printf 'module\n' > "$module"
    done
    [[ ${FAKE_EXTRA_MODULE-0} == 0 ]] || printf 'extra\n' > "$mt76_dir/extra.ko"
fi
EOF
    cat > "$fake_bin/nproc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 1
EOF
    chmod +x "$fake_bin/git" "$fake_bin/make" "$fake_bin/nproc"

    PATH="$fake_bin:$PATH" \
    FAKE_KDIR_FIXTURE="$kdir" \
    FAKE_MAKE_LOG="$make_log" \
    FAKE_GIT_LOG="$git_log" \
    LLVM=1 LLVM_IAS=0 CC=clang-test LD=ld.lld-test \
    AR=llvm-ar-test NM=llvm-nm-test STRIP=llvm-strip-test \
    OBJCOPY=llvm-objcopy-test OBJDUMP=llvm-objdump-test \
    READELF=llvm-readelf-test HOSTCC=host-clang-test \
    HOSTCXX=host-clangxx-test \
        "$BUILD_LEGACY" > "$output"

    while IFS= read -r line; do
        ((calls += 1))
        line=" $line"
        for expected in "${expected_args[@]}"; do
            [[ $line == *" $expected "* ]] ||
                fail "make call $calls omitted command-line $expected"
        done
    done < "$make_log"
    [[ $calls -eq 3 ]] || fail "expected 3 make calls, got $calls"

    : > "$make_log"
    : > "$git_log"
    PATH="$fake_bin:$PATH" \
    FAKE_KDIR_FIXTURE="$kdir" \
    FAKE_MAKE_LOG="$make_log" \
    FAKE_GIT_LOG="$git_log" \
    KERNEL_REF=current-native \
    WIRELESS_NEXT_REF=ca800a9302764c445de0da0e84d2252400a770ee \
    FAKE_REQUIRE_SYMVERS_FORMAT=1 \
    CC=clang-test \
        "$BUILD_LEGACY" > "$output"

    line=$(grep ' modules ' "$make_log")
    kbuild_dir=''
    mt76_dir=''
    previous=''
    for arg in $line; do
        if [[ $previous == -C ]]; then
            kbuild_dir=$arg
        fi
        case $arg in
            M=*) mt76_dir=${arg#M=} ;;
        esac
        previous=$arg
    done
    [[ -n $kbuild_dir && $mt76_dir == "$kbuild_dir/drivers/net/wireless/mediatek/mt76" ]] ||
        fail 'current-native build did not use one wireless-next source/header generation'
    if grep -A1 '^Compatibility patches:$' "$output" | grep -Eq '^(action-frame|eml|nan|aql|alloc-flex|rx-link-sta)$'; then
        fail 'current-native build selected a compatibility patch'
    fi

    if PATH="$fake_bin:$PATH" \
        FAKE_KDIR_FIXTURE="$kdir" \
        FAKE_MAKE_LOG="$make_log" \
        FAKE_GIT_LOG="$git_log" \
        FAKE_EXTRA_MODULE=1 \
        CC=clang-test \
            "$BUILD_LEGACY" > "$output" 2>&1; then
        fail 'API build accepted an unexpected sixth module output'
    fi
}

assert_aql_without_symvers() {
    local kdir actual
    local stderr="$TEST_DIR/no-aql-symvers.stderr"

    kdir=$(make_fixture v7.1)
    printf '%s\n' \
        '#define IEEE80211_EML_CAP_EML_PADDING_DELAY 0' \
        '#define IEEE80211_EML_CAP_EML_TRANSITION_DELAY 0' > "$kdir/include/linux/ieee80211-eht.h"
    printf '%s\n' 'void ieee80211_nan_cluster_joined(' >> "$kdir/include/net/mac80211.h"
    rm "$kdir/Module.symvers"

    if ! actual=$("$COMPAT" detect "$kdir" 2> "$stderr"); then
        fail 'detection failed without an AQL declaration'
    fi
    [[ ! -s $stderr ]] || fail 'detection read missing Module.symvers without an AQL declaration'
    [[ $actual == $'aql\nrx-link-sta' ]] ||
        fail "missing AQL declaration: expected aql and rx-link-sta, got $(printf '%q' "$actual")"
}

assert_unsupported() {
    local header=$1
    local content=$2
    local kdir output

    kdir=$(make_fixture current)
    printf '%s\n' "$content" > "$kdir/$header"
    if output=$("$COMPAT" detect "$kdir" 2>&1); then
        fail "$header: unsupported generation was accepted"
    fi
    [[ $output == *"$header"* ]] || fail "$header: diagnostic did not name unsupported header"
}

copy_wireless_next_tree() {
    local remote_head source_file
    local -a source_files=(
        drivers/net/wireless/mediatek/mt76/agg-rx.c
        drivers/net/wireless/mediatek/mt76/mac80211.c
        drivers/net/wireless/mediatek/mt76/mt76.h
        drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c
        drivers/net/wireless/mediatek/mt76/mt76_connac_mcu.c
        drivers/net/wireless/mediatek/mt76/mt76_connac_mcu.h
        drivers/net/wireless/mediatek/mt76/mt7925/Makefile
        drivers/net/wireless/mediatek/mt76/mt7925/init.c
        drivers/net/wireless/mediatek/mt76/mt7925/mac.c
        drivers/net/wireless/mediatek/mt76/mt7925/main.c
        drivers/net/wireless/mediatek/mt76/mt7925/mcu.c
        drivers/net/wireless/mediatek/mt76/mt7925/nan.c
        drivers/net/wireless/mediatek/mt76/mt7925/nan.h
        drivers/net/wireless/mediatek/mt76/mt7925/regd.c
        drivers/net/wireless/mediatek/mt76/mt7925/regd.h
        drivers/net/wireless/mediatek/mt76/mt792x.h
        drivers/net/wireless/mediatek/mt76/mt792x_core.c
        drivers/net/wireless/mediatek/mt76/mt7996/mac.c
        drivers/net/wireless/mediatek/mt76/tx.c
    )

    remote_head=$(git ls-remote "$WIRELESS_NEXT_REPO" refs/heads/main)
    read -r WIRELESS_NEXT_SHA _ <<< "$remote_head"
    [[ $WIRELESS_NEXT_SHA =~ ^[0-9a-f]{40}$ ]] || fail 'could not resolve wireless-next/main'

    git init --quiet "$SOURCE_DIR"
    for source_file in "${source_files[@]}"; do
        mkdir -p "$SOURCE_DIR/$(dirname "$source_file")"
        curl --fail --location --silent --show-error \
            "$WIRELESS_NEXT_PLAIN/$source_file?id=$WIRELESS_NEXT_SHA" \
            --output "$SOURCE_DIR/$source_file"
    done
    git -C "$SOURCE_DIR" add .
    git -C "$SOURCE_DIR" \
        -c user.name='Compatibility Test' \
        -c user.email='compat-test@example.invalid' \
        commit --quiet -m "Record wireless-next $WIRELESS_NEXT_SHA"
}

reset_source() {
    git -C "$SOURCE_DIR" reset --hard --quiet HEAD
    git -C "$SOURCE_DIR" clean -fdq
}

assert_action_patch_scope() {
    reset_source
    git -C "$SOURCE_DIR" apply --check "$ACTION_PATCH"
    git -C "$SOURCE_DIR" apply "$ACTION_PATCH"

    grep -Fq 'IEEE80211_MIN_ACTION_SIZE + 1 + 1 + 2' \
        "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c" ||
        fail 'action patch did not adapt mt76_connac_mac.c'
    grep -Fq 'mgmt->u.action.u.addba_req.action_code' \
        "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mac.c" ||
        fail 'action patch did not adapt mt7925/mac.c'
    grep -Fq 'IEEE80211_EML_CAP_EML_PADDING_DELAY' \
        "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c" ||
        fail 'action patch changed the EML API'
    grep -Fq 'IEEE80211_MIN_ACTION_SIZE(action_code)' \
        "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7996/mac.c" ||
        fail 'action patch changed mt7996'
    git -C "$SOURCE_DIR" apply --reverse --check "$ACTION_PATCH"
}

make_apply_fixture() {
    local action_generation=$1
    local eml_generation=$2
    local rx_generation=$3
    local kdir

    kdir=$(make_fixture current "$rx_generation")
    if [[ $action_generation == legacy ]]; then
        printf '%s\n' '#define IEEE80211_MIN_ACTION_SIZE 24' > "$kdir/include/linux/ieee80211.h"
    fi
    if [[ $eml_generation == legacy ]]; then
        printf '%s\n' \
            '#define IEEE80211_EML_CAP_EMLSR_PADDING_DELAY 0' \
            '#define IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY 0' > "$kdir/include/linux/ieee80211-eht.h"
    fi
    printf '%s\n' "$kdir"
}

assert_applied_patches() {
    local action_generation=$1
    local eml_generation=$2
    local rx_generation=$3
    local expected=$4
    local kdir actual

    reset_source
    kdir=$(make_apply_fixture "$action_generation" "$eml_generation" "$rx_generation")
    actual=$("$COMPAT" apply "$SOURCE_DIR" "$kdir")
    [[ $actual == "$expected" ]] ||
        fail "$action_generation/$eml_generation: expected $(printf '%q' "$expected"), got $(printf '%q' "$actual")"

    if [[ $action_generation == legacy ]]; then
        grep -Fq 'IEEE80211_MIN_ACTION_SIZE + 1 + 1 + 2' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c" ||
            fail 'selected action patch did not adapt mt76_connac_mac.c'
        grep -Fq 'mgmt->u.action.u.addba_req.action_code' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mac.c" ||
            fail 'selected action patch did not adapt mt7925/mac.c'
        git -C "$SOURCE_DIR" apply --reverse --check "$ACTION_PATCH"
    else
        grep -Fq 'IEEE80211_MIN_ACTION_SIZE(addba_req.capab)' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt76_connac_mac.c" ||
            fail 'unselected action patch changed mt76_connac_mac.c'
        grep -Fq 'IEEE80211_MIN_ACTION_SIZE(action_code)' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mac.c" ||
            fail 'unselected action patch changed mt7925/mac.c'
    fi

    if [[ $eml_generation == legacy ]]; then
        grep -Fq 'IEEE80211_EML_CAP_EMLSR_PADDING_DELAY' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c" ||
            fail 'selected EML patch did not adapt the padding-delay name'
        grep -Fq 'IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c" ||
            fail 'selected EML patch did not adapt the transition-delay name'
        git -C "$SOURCE_DIR" apply --reverse --check "$EML_PATCH"
    else
        grep -Fq 'IEEE80211_EML_CAP_EML_PADDING_DELAY' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c" ||
            fail 'unselected EML patch changed the padding-delay name'
        grep -Fq 'IEEE80211_EML_CAP_EML_TRANSITION_DELAY' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c" ||
            fail 'unselected EML patch changed the transition-delay name'
    fi

    if [[ $rx_generation == legacy ]]; then
        grep -Fq 'ieee80211_rx_list(hw, sta, skb, &list)' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mac80211.c" ||
            fail 'selected RX patch did not restore the station-based RX call'
        grep -Fq 'struct ieee80211_sta **sta)' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mac80211.c" ||
            fail 'selected RX patch did not restore the station-based convert signature'
        git -C "$SOURCE_DIR" apply --reverse --check "$RX_LINK_STA_PATCH"
    else
        grep -Fq 'ieee80211_rx_list(hw, link_sta, skb, &list)' \
            "$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/mac80211.c" ||
            fail 'unselected RX patch changed the link-station RX call'
    fi

    if [[ $action_generation == current && $eml_generation == current &&
          $rx_generation == current ]]; then
        git -C "$SOURCE_DIR" diff --quiet ||
            fail 'current fixture changed the wireless-next source'
    fi
}

assert_v7_0_patch_scope() {
    local kdir actual mt76_dir

    reset_source
    kdir=$(make_fixture v7.0)
    actual=$("$COMPAT" apply "$SOURCE_DIR" "$kdir")
    [[ $actual == $'action-frame\neml\nnan\naql\nrx-link-sta' ]] ||
        fail "v7.0: expected all compatibility patches, got $(printf '%q' "$actual")"

    mt76_dir="$SOURCE_DIR/drivers/net/wireless/mediatek/mt76"
    if grep -Rqs 'NL80211_IFTYPE_NAN_DATA' \
        "$mt76_dir/mt7925" "$mt76_dir/mt792x.h" \
        "$mt76_dir/mt792x_core.c" "$mt76_dir/mt76_connac_mcu.c"; then
        fail 'NAN host references remain after v7.0 patch selection'
    fi
    grep -q 'nan.o' "$mt76_dir/mt7925/Makefile" &&
        fail 'nan.o remains enabled after v7.0 patch selection'
    grep -q 'ieee80211_txq_aql_pending' "$mt76_dir/tx.c" &&
        fail 'AQL helper remains after v7.0 patch selection'
    grep -Fq 'if (test_bit(MT_WCID_FLAG_PS, &wcid->flags))' "$mt76_dir/tx.c" ||
        fail 'legacy power-save guard is missing after v7.0 patch selection'
}

assert_v6_18_patch_scope() {
    local kdir actual agg_rx

    reset_source
    kdir=$(make_fixture v6.18)
    actual=$("$COMPAT" apply "$SOURCE_DIR" "$kdir")
    [[ $actual == $'action-frame\neml\nnan\naql\nalloc-flex\nrx-link-sta' ]] ||
        fail "v6.18: expected all compatibility patches, got $(printf '%q' "$actual")"

    agg_rx="$SOURCE_DIR/drivers/net/wireless/mediatek/mt76/agg-rx.c"
    grep -Fq 'kzalloc(struct_size(tid, reorder_buf, size), GFP_KERNEL)' "$agg_rx" ||
        fail 'legacy flex allocation was not restored for v6.18'
    grep -q 'kzalloc_flex' "$agg_rx" &&
        fail 'kzalloc_flex remains after v6.18 patch selection'
    git -C "$SOURCE_DIR" apply --reverse --check "$ALLOC_FLEX_PATCH"
}

assert_failed_preflight_is_atomic() {
    local kdir output makefile content changed_files
    local context='obj-$(CONFIG_MT7925E) += mt7925e.o'
    local makefile_path='drivers/net/wireless/mediatek/mt76/mt7925/Makefile'

    reset_source
    kdir=$(make_fixture v7.0)
    makefile="$SOURCE_DIR/$makefile_path"
    content=$(<"$makefile")
    [[ $content == *"$context"* ]] || fail 'NAN mutation context is missing'
    printf '%s\n' "${content/"$context"/"$context # mutated"}" > "$makefile"

    if output=$("$COMPAT" apply "$SOURCE_DIR" "$kdir" 2>&1); then
        fail 'mutated NAN context was accepted'
    fi
    changed_files=$(git -C "$SOURCE_DIR" diff --name-only)
    [[ $changed_files == "$makefile_path" ]] ||
        fail "failed preflight changed source files: $(printf '%q' "$changed_files")"
}

assert_patches v6.18 $'action-frame\neml\nnan\naql\nalloc-flex\nrx-link-sta'
assert_patches v7.0 $'action-frame\neml\nnan\naql\nrx-link-sta'
assert_patches v7.1 $'eml\nnan\naql\nrx-link-sta'
assert_patches v7.2 $'aql\nrx-link-sta'
assert_patches current ''
assert_nan_contract_fail_closed
assert_kbuild_tool_args
assert_aql_without_symvers

assert_unsupported include/linux/ieee80211.h '#define IEEE80211_MIN_ACTION_LENGTH 24'
assert_unsupported include/linux/ieee80211-eht.h '#define IEEE80211_EML_CAP_UNKNOWN 0'
assert_unsupported include/net/mac80211.h 'void ieee80211_rx_list(void);'

copy_wireless_next_tree
assert_action_patch_scope
assert_v6_18_patch_scope
assert_v7_0_patch_scope
assert_failed_preflight_is_atomic
assert_applied_patches legacy legacy current $'action-frame\neml'
assert_applied_patches legacy current current 'action-frame'
assert_applied_patches current legacy current 'eml'
assert_applied_patches current current legacy $'rx-link-sta'
assert_applied_patches current current current ''

printf 'Compatibility detection and split patch tests passed at %s.\n' "$WIRELESS_NEXT_SHA"
