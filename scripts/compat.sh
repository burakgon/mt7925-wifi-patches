#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
    printf 'compat.sh: %s\n' "$*" >&2
    exit 1
}

has_tokens() {
    local file=$1 token

    shift
    [[ -f $file ]] || return 1
    for token in "$@"; do
        grep -Fq -- "$token" "$file" || return 1
    done
}

struct_has_members() {
    local file=$1 name=$2 body member

    shift 2
    body=$(awk -v declaration="struct $name {" '
        $0 == declaration { inside = 1 }
        inside { print }
        inside && $0 == "};" { exit }
    ' "$file")
    [[ $body == *"struct $name {"* ]] || return 1
    for member in "$@"; do
        [[ $body == *"$member"* ]] || return 1
    done
}

rx_list_has_arg_type() {
    local mac80211=$1 type=$2 declaration

    declaration=$(awk '
        /^void ieee80211_rx_list\(/ { inside = 1 }
        inside { print }
        inside && /;/ { exit }
    ' "$mac80211")
    [[ -n $declaration && $declaration == *"$type"* ]]
}

has_nan_api() {
    local ieee80211_nan=$1 nl80211=$2 cfg80211=$3 mac80211=$4

    has_tokens "$ieee80211_nan" \
        '#define NAN_OP_MODE_PHY_MODE_MASK' \
        '#define NAN_DEV_CAPA_EXT_KEY_ID_SUPPORTED' &&
    has_tokens "$nl80211" \
        'NL80211_IFTYPE_NAN,' \
        'NL80211_IFTYPE_NAN_DATA,' \
        'NL80211_EXT_FEATURE_SECURE_NAN,' &&
    has_tokens "$cfg80211" \
        '#define CFG80211_NAN_SCHED_NUM_TIME_SLOTS' \
        '#define CFG80211_NAN_MAX_PEER_MAPS' \
        '#define CFG80211_NAN_INVALID_MAP_ID' \
        'WIPHY_NAN_FLAGS_CONFIGURABLE_SYNC =' \
        'WIPHY_NAN_FLAGS_USERSPACE_DE' \
        'void cfg80211_next_nan_dw_notif(' &&
    struct_has_members "$cfg80211" cfg80211_nan_band_config \
        'struct ieee80211_channel *chan;' \
        's8 rssi_close;' \
        's8 rssi_middle;' \
        'u8 awake_dw_interval;' &&
    struct_has_members "$cfg80211" cfg80211_nan_conf \
        'u8 master_pref;' \
        'u8 bands;' \
        'u8 cluster_id[ETH_ALEN]' \
        'u16 scan_period;' \
        'u16 scan_dwell_time;' \
        'u8 discovery_beacon_interval;' \
        'bool enable_dw_notification;' \
        'struct cfg80211_nan_band_config band_cfgs[' &&
    struct_has_members "$cfg80211" wiphy_nan_capa \
        'u32 flags;' \
        'u8 op_mode;' \
        'u8 n_antennas;' \
        'u16 max_channel_switch_time;' \
        'u8 dev_capabilities;' \
        'struct ieee80211_sta_ht_cap ht;' \
        'struct ieee80211_sta_vht_cap vht;' \
        'struct ieee80211_sta_he_cap he;' \
        '} phy;' &&
    struct_has_members "$cfg80211" wiphy \
        'u8 nan_supported_bands;' \
        'struct wiphy_nan_capa nan_capa;' &&
    has_tokens "$mac80211" \
        'BSS_CHANGED_NAN_LOCAL_SCHED' \
        'struct wireless_dev *ieee80211_vif_to_wdev(' \
        'void ieee80211_nan_sched_update_done(' \
        'void ieee80211_nan_cluster_joined(' \
        'bool ieee80211_vif_nan_started(' &&
    struct_has_members "$mac80211" ieee80211_nan_channel \
        'struct ieee80211_chanctx_conf *chanctx_conf;' \
        'u8 channel_entry[' &&
    struct_has_members "$mac80211" ieee80211_nan_peer_map \
        'u8 map_id;' \
        'struct ieee80211_nan_channel *slots[' &&
    struct_has_members "$mac80211" ieee80211_nan_peer_sched \
        'u16 max_chan_switch;' \
        'struct ieee80211_nan_peer_map maps[' \
        'u8 n_channels;' \
        'struct ieee80211_nan_channel channels[]' &&
    struct_has_members "$mac80211" ieee80211_nan_sched_cfg \
        'struct ieee80211_nan_channel *schedule[' \
        'u8 avail_blob[' \
        'u16 avail_blob_len;' \
        'bool deferred;' &&
    struct_has_members "$mac80211" ieee80211_vif_cfg \
        'struct ieee80211_nan_sched_cfg nan_sched;' &&
    struct_has_members "$mac80211" ieee80211_vif \
        'struct ieee80211_vif_cfg cfg;' &&
    struct_has_members "$mac80211" ieee80211_sta \
        'struct ieee80211_sta __rcu *nmi;' \
        'struct ieee80211_nan_peer_sched *nan_sched;' &&
    struct_has_members "$mac80211" ieee80211_ops \
        '(*start_nan)(' \
        '(*stop_nan)(' \
        '(*nan_change_conf)(' \
        '(*nan_peer_sched_changed)('
}

detect_patches() {
    local kdir=$1
    local action="$kdir/include/linux/ieee80211.h"
    local eml="$kdir/include/linux/ieee80211-eht.h"
    local slab="$kdir/include/linux/slab.h"
    local ieee80211_nan="$kdir/include/linux/ieee80211-nan.h"
    local nl80211="$kdir/include/uapi/linux/nl80211.h"
    local cfg80211="$kdir/include/net/cfg80211.h"
    local mac80211="$kdir/include/net/mac80211.h"
    local symvers="$kdir/Module.symvers"
    local file current_action=0 legacy_action=0 current_eml=0 legacy_eml=0
    local current_rx=0 legacy_rx=0

    for file in "$action" "$slab" "$nl80211" "$cfg80211" "$mac80211"; do
        [[ -f $file ]] || die "required file not found: $file"
    done

    [[ -f $eml ]] || eml=$action

    grep -Eq '^[[:space:]]*#define[[:space:]]+IEEE80211_MIN_ACTION_SIZE\(' "$action" && current_action=1
    grep -Eq '^[[:space:]]*#define[[:space:]]+IEEE80211_MIN_ACTION_SIZE[[:space:]]+' "$action" && legacy_action=1
    [[ $((current_action + legacy_action)) -eq 1 ]] || die "unsupported action API in $action"

    if grep -q 'IEEE80211_EML_CAP_EML_PADDING_DELAY' "$eml" &&
       grep -q 'IEEE80211_EML_CAP_EML_TRANSITION_DELAY' "$eml"; then
        current_eml=1
    fi
    if grep -q 'IEEE80211_EML_CAP_EMLSR_PADDING_DELAY' "$eml" &&
       grep -q 'IEEE80211_EML_CAP_EMLSR_TRANSITION_DELAY' "$eml"; then
        legacy_eml=1
    fi
    [[ $((current_eml + legacy_eml)) -eq 1 ]] || die "unsupported EML API in $eml"

    rx_list_has_arg_type "$mac80211" 'struct ieee80211_link_sta *' && current_rx=1
    rx_list_has_arg_type "$mac80211" 'struct ieee80211_sta *' && legacy_rx=1
    [[ $((current_rx + legacy_rx)) -eq 1 ]] || die "unsupported RX API in $mac80211"

    ((current_action)) || printf '%s\n' action-frame
    ((current_eml)) || printf '%s\n' eml

    if ! has_nan_api "$ieee80211_nan" "$nl80211" "$cfg80211" "$mac80211"; then
        printf '%s\n' nan
    fi

    if ! grep -q 'ieee80211_txq_aql_pending' "$mac80211"; then
        printf '%s\n' aql
    elif [[ ! -f $symvers ]]; then
        die "required file not found: $symvers"
    elif ! grep -q '[[:space:]]ieee80211_txq_aql_pending[[:space:]]' "$symvers"; then
        printf '%s\n' aql
    fi

    grep -q 'kzalloc_flex' "$slab" || printf '%s\n' alloc-flex

    ((current_rx)) || printf '%s\n' rx-link-sta
}

apply_patches() {
    local source=$1
    local kdir=$2
    local detected patch_id patch
    local -a patch_ids=() patch_files=()

    git -C "$source" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "source is not a git worktree: $source"
    detected=$(detect_patches "$kdir")
    [[ -n $detected ]] || return 0

    while IFS= read -r patch_id; do
        patch="$ROOT_DIR/patches/legacy-$patch_id-api.patch"
        [[ -f $patch ]] || die "required patch not found: $patch"
        patch_ids+=("$patch_id")
        patch_files+=("$patch")
    done <<< "$detected"

    git -C "$source" apply --check "${patch_files[@]}"
    git -C "$source" apply "${patch_files[@]}"
    printf '%s\n' "${patch_ids[@]}"
}

usage() {
    printf 'usage: %s detect KDIR | apply SOURCE_DIR KDIR\n' "${0##*/}" >&2
    exit 2
}

case ${1-} in
    detect)
        [[ $# -eq 2 ]] || usage
        detect_patches "$2"
        ;;
    apply)
        [[ $# -eq 3 ]] || usage
        apply_patches "$2" "$3"
        ;;
    *)
        usage
        ;;
esac
