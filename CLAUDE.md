# CLAUDE.md

This file defines the maintainer contract for this repository.

## Scope

The project builds the MT7925 PCIe driver from `wireless-next` as exactly five
external modules: `mt76`, `mt76_connac_lib`, `mt792x_lib`, `mt7925_common`, and
`mt7925e`. Keep documentation and build selectors limited to that scope.

## Source And Compatibility Contract

`mt76-rebuild.sh` fetches `wireless-next/main`, validates the resolved
40-character SHA, forces a detached checkout at that revision, and cleans it
before each build. A nonblocking repository-local lock covers source reset
through installer handoff. Current HEAD is intentional and can break when
upstream source changes. Never describe it as a stable source pin.

`scripts/compat.sh` probes target headers and `Module.symvers` rather than
selecting by release number. Its stdout is the stable patch-ID stream consumed
by build metadata:

- `action-frame`
- `eml`
- `nan`
- `aql`
- `alloc-flex`
- `rx-link-sta`

Legacy NAN compatibility disables NAN and NDI as one unit when the host NAN
contract is incomplete. Linux 6.18, 7.0, and 7.1 select that path. AQL
compatibility restores the pre-AQL MT7925 sleeping-station branch instead of
calling an unavailable or unexported helper; the tested old rows through Linux
7.2 select it.

Linux 6.18 additionally selects `alloc-flex`, restoring the equivalent legacy
`kzalloc(struct_size(...), GFP_KERNEL)` allocation because its slab headers do
not provide `kzalloc_flex()`.

`rx-link-sta` restores the station-based `ieee80211_rx_list()` contract after
wireless-next switched the public RX API to link stations. Every tested kernel
row through Linux 7.2 selects it; a source/header generation that already
declares the link-station argument uses the native path.

Patch application is atomic: every selected patch passes `git apply --check`
before source changes. Put compatibility changes in independently selectable
files under `patches/`; do not tell users to edit the cleaned source checkout.

Expected source-tag API coverage:

| Headers | Selected compatibility |
| --- | --- |
| Linux 6.18 | action-frame, eml, nan, aql, alloc-flex, rx-link-sta |
| Linux 7.0 | action-frame, eml, nan, aql, rx-link-sta |
| Linux 7.1 | eml, nan, aql, rx-link-sta |
| Linux 7.2 | aql, rx-link-sta |
| Current native API | none |

Feature probes remain authoritative when a distribution backports APIs.

## Rebuild Contract

Run the script as a normal user:

```bash
./mt76-rebuild.sh
```

It must reject direct root execution, perform source and build work without
privilege, print the running kernel, compiler, source SHA, and patch IDs, and
invoke `sudo` only for `scripts/module-overlay.sh install`.

For the supported Clang path:

```bash
LLVM=1 ./mt76-rebuild.sh
```

Preserve explicit Kbuild tool variables and the PCIe-only selectors. The build
must produce and validate these files before privilege escalation:

- `mt76.ko`
- `mt76-connac-lib.ko`
- `mt792x-lib.ko`
- `mt7925-common.ko`
- `mt7925e.ko`

Each staged file must be non-empty ELF relocatable output whose first vermagic
token exactly equals `uname -r`. `.build-info` contains exactly one each of
`kernel`, `source_sha`, `compiler`, and comma-separated `patches`.

When signature enforcement or lockdown is active, unsigned output must be
refused before installation. There is no automatic key enrollment or signing
flow. Refer users to the kernel's
[module signing documentation](https://docs.kernel.org/admin-guide/module-signing.html)
for a reviewed manual process.

## Overlay And Revert Contract

The privileged helper owns only the current kernel's external overlay:

```text
/lib/modules/$KVER/updates/mt7925-wifi-patches/
```

Transaction `new` and `previous` directories live outside the kernel version
tree at `/lib/modules/.mt7925-wifi-patches/$KVER/`. A nonblocking global
`/lib/modules` lock serializes direct install and revert calls.

An install stages a new directory, unloads the five-module stack, atomically
activates the new overlay, runs `depmod -a "$KVER"`, verifies all five `modinfo`
resolutions, activates exact optional settings, loads `mt7925e`, and verifies
the complete loaded stack. Verified state is committed before previous-overlay
cleanup, so cleanup failure only warns. A failed
transaction returns to the previous overlay or stock resolution and reports
recovery verification failures. Distribution-owned module files under
`/lib/modules/$KVER/kernel/` are never installation targets.

The user-facing revert is:

```bash
./mt76-revert.sh
```

`--yes` skips confirmation. Revert is scoped to `uname -r`, verifies stock
resolution for all five modules, reloads the stack, and is repeatable.

## Optional Settings Contract

Power settings are opt-in only:

- `--disable-aspm` manages
  `/etc/modprobe.d/99-mt7925-wifi-patches.conf`.
- `--disable-power-save` manages
  `/etc/NetworkManager/dispatcher.d/99-mt7925-wifi-patches`.

The dispatcher acts only on a NetworkManager-managed interface whose driver
module resolves to `mt7925e`. Both options can increase power consumption.
`--disable-power-save` requires both `iw` and NetworkManager before transaction
writes.
Refuse user-owned target files. Remove only byte-identical project-generated
settings; preserve locally changed files and print manual recovery paths when a
transaction cannot restore prior content.

## Status And Desktop Contract

`./mt76-check.sh --text` is deterministic and does not require a notifier. It
uses `modinfo -n mt7925e`, overlay metadata, `/proc/modules`, and the canonical
sysfs driver-module link. Exit `0` means the custom driver is loaded; stock,
unloaded, stale, missing, and unknown states are nonzero.
Only the current kernel's `kernel/` tree is stock; other non-project paths are
unknown external drivers. ASPM status comes from the live module parameter when
available, and optional settings are selected only when byte-identical to their
canonical generated content.

Desktop entries use `Exec=mt76-check.sh`. User instructions must install the
checker first:

```bash
install -Dm755 mt76-check.sh "$HOME/.local/bin/mt76-check.sh"
install -Dm644 mt76-check.desktop \
  "$HOME/.config/autostart/mt76-check.desktop"
install -Dm644 mt76-status.desktop \
  "$HOME/.local/share/applications/mt76-status.desktop"
```

## Firmware Contract

Firmware stays distribution-managed; the rebuild does not write under
`/lib/firmware`. Keep README package commands specific to Fedora, Ubuntu,
Debian, and Arch Linux.

## CI And Verification

CI resolves wireless-next HEAD once and passes that SHA to all six matrix
entries: GCC on Linux 6.18, 7.0, 7.1, and 7.2, Clang/`LLVM=1` on Linux 7.1,
and a current-native GCC row using one wireless-next source/header generation.
These jobs are API-only checks because `modules_prepare` lacks a complete
`Module.symvers`. The separate Fedora Rawhide job selects its
package-owned `kernel-devel` tree, requires the wireless headers and real
`Module.symvers`, and uses strict modpost. Every build log must print the kernel
ref, compiler, source SHA, detected feature states, and patch IDs even when
feature detection fails.

Run the full local suite after any behavioral, documentation, or workflow
change:

```bash
bash -n mt76-rebuild.sh mt76-revert.sh mt76-check.sh scripts/*.sh tests/*.sh
./tests/test-compat.sh
./tests/test-rebuild.sh
./tests/test-module-overlay.sh
./tests/test-real-depmod.sh
./tests/test-status.sh
./tests/test-workflow.sh
desktop-file-validate mt76-check.desktop mt76-status.desktop
git diff --check
```

Keep claims bounded by these checks. The API matrix is not evidence for every
kernel configuration, distribution, device, or module load path.
