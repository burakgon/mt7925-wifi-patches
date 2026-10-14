#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/compat-patch.yml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Fq 'empty_tree=$(git hash-object -t tree /dev/null)' "$WORKFLOW" ||
    fail 'static GitHub Actions gate does not cover the complete tracked tree'
grep -Fq 'git diff --check "$empty_tree" HEAD' "$WORKFLOW" ||
    fail 'static GitHub Actions gates omit an effective git diff --check'

native_row=$(awk '
    /- kernel: current-native/ { capture = 1 }
    capture { print }
    capture && /patches:/ { exit }
' "$WORKFLOW")
[[ $native_row == *'toolchain: gcc'* && $native_row == *'patches: none'* ]] ||
    fail 'API matrix omits the no-patch current-native row'
[[ $(grep -Fc -- '- kernel: current-native' "$WORKFLOW") -eq 1 ]] ||
    fail 'current-native API row must appear exactly once'

v618_row=$(awk '
    /- kernel: v6.18/ { capture = 1 }
    capture { print }
    capture && /patches:/ { exit }
' "$WORKFLOW")
[[ $v618_row == *'patches: action-frame,eml,nan,aql,alloc-flex,rx-link-sta'* ]] ||
    fail 'Linux 6.18 matrix row omits alloc-flex or rx-link-sta compatibility'
grep -Fq 'alloc-flex=%s' "$WORKFLOW" ||
    fail 'workflow diagnostics omit alloc-flex feature state'
grep -Fq 'rx-link-sta=%s' "$WORKFLOW" ||
    fail 'workflow diagnostics omit rx-link-sta feature state'

printf 'Workflow static gate and current-native matrix contract passed.\n'
