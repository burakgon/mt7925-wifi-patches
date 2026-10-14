# MT7925 PCIe Driver Overlay

This repository builds the MT7925 PCIe driver from the current
`wireless-next` development tree for the running Linux kernel. It installs five
external modules without changing distribution-owned module files:

- `mt76`
- `mt76_connac_lib`
- `mt792x_lib`
- `mt7925_common`
- `mt7925e`

The source moves with `wireless-next/main`. A build that succeeds today can fail
after upstream changes. Each run prints the exact 40-character source SHA,
compiler, and selected compatibility patch IDs; include those values with any
failure report.

## Tested Scope

CI tests these kernel API combinations against one resolved wireless-next SHA:

| Target kernel source | Toolchain | CI evidence |
| --- | --- | --- |
| Linux 6.18 | GCC | API compile check |
| Linux 7.0 | GCC | API compile check |
| Linux 7.1 | GCC | API compile check |
| Linux 7.2 | GCC | API compile check |
| Linux 7.1 | Clang with `LLVM=1` | API compile check |
| Current wireless-next APIs | GCC | API compile check, same tree |

Legacy NAN compatibility disables NAN and NDI as one unit when the host NAN
contract is incomplete. Linux 6.18, 7.0, and 7.1 select that path, so those
rows do not provide NAN Data Interface support. The AQL compatibility path,
selected by the tested old rows through Linux 7.2, restores the
pre-AQL MT7925 sleeping-station branch instead of calling an unavailable or
unexported AQL helper.

Linux 6.18 also selects `alloc-flex`: current mt76's `kzalloc_flex()` call is
rewritten to the overflow-safe legacy `kzalloc(struct_size(...), GFP_KERNEL)`
form because that helper was introduced later.

Every tested kernel row through Linux 7.2 also selects `rx-link-sta`:
wireless-next now hands received frames to mac80211 with a link station, while
those headers still take a station in `ieee80211_rx_list()`. The patch restores
the station-based call and the matching RX status link fields, and only a
source/header generation that already provides the link-station API uses the
native path.

Source-tag and current-native jobs use `modules_prepare` and permit unresolved
base-kernel symbols, so they test API compatibility, not whether a module can
be loaded. A separate CI job builds against Fedora Rawhide's packaged
`kernel-devel` tree and real
`Module.symvers` with strict modpost, exact-module, dependency, and vermagic
checks. This matrix does not certify other kernel configurations,
distributions, or devices. The weekly CI run is the moving-HEAD canary.

## Requirements

Install headers that exactly match `uname -r`, plus the normal kernel module
build tools.

Fedora:

```bash
sudo dnf install "kernel-devel-$(uname -r)" gcc make git bc bison flex \
  elfutils-libelf-devel openssl-devel kmod file iw
```

Ubuntu:

```bash
sudo apt update
sudo apt install "linux-headers-$(uname -r)" build-essential git bc bison flex \
  libelf-dev libssl-dev kmod file iw
```

Arch Linux package names must match the installed kernel flavor. Use
`linux-headers` for `linux`, `linux-lts-headers` for `linux-lts`, or
`linux-zen-headers` for `linux-zen`:

```bash
sudo pacman -S --needed base-devel git bc bison flex openssl libelf kmod file \
  iw linux-headers
```

For a Clang build, also install Clang, LLVM, and LLD with the distribution
package manager, then set `LLVM=1` when rebuilding.

## Build And Install

Run the orchestrator as your normal user, without whole-script privilege:

```bash
./mt76-rebuild.sh
```

For Clang:

```bash
LLVM=1 ./mt76-rebuild.sh
```

The script fetches and cleans the current `wireless-next/main`, feature-probes
the target headers, applies only the required action-frame, EML, NAN, AQL,
allocation, and RX link-station compatibility patches, and builds only the five
modules listed above. Unknown
header or source shapes stop before installation. A repository-local lock
rejects concurrent rebuilds before either run can modify the shared source
checkout.

The privileged helper installs the staged modules at:

```text
/lib/modules/$(uname -r)/updates/mt7925-wifi-patches/
```

Staged and previous transaction copies stay outside the depmod-scanned kernel
tree under `/lib/modules/.mt7925-wifi-patches/$(uname -r)/`.

It unloads the active stack, swaps the external overlay transactionally, runs
`depmod`, verifies that all five module names resolve to the new path, reloads
`mt7925e`, and verifies the loaded dependency stack. A failed transaction
automatically returns to the previous overlay or the distribution modules and
reports any recovery verification problem. Files below the kernel package's
`kernel/` directory remain unchanged.

Rebuild after booting each new kernel because overlays are scoped by
`uname -r`.

## Secure Boot And Signing

The rebuild does not create or enroll a signing key. If module signature
enforcement or kernel lockdown is active, it checks every built module's signer
and refuses unsigned output before installation.

Use a reviewed manual signing flow with a key enrolled for the machine. The
kernel documentation describes `scripts/sign-file`, key formats, and signing
configuration: [Kernel module signing facility](https://docs.kernel.org/admin-guide/module-signing.html).
This repository does not automate that security-sensitive workflow.

## Optional Stability Settings

No power setting changes by default. They are explicit rebuild options:

```bash
./mt76-rebuild.sh --disable-aspm
./mt76-rebuild.sh --disable-power-save
./mt76-rebuild.sh --disable-aspm --disable-power-save
```

`--disable-aspm` installs a project-owned `mt7925e disable_aspm=1` modprobe
configuration. It can reduce PCIe power-management problems at the cost of
higher power use.

`--disable-power-save` installs a NetworkManager dispatcher that turns power
save off only for a managed interface bound to `mt7925e`. It can reduce latency
at the cost of battery life. This option requires both `iw` and NetworkManager.

The installer refuses to replace a user-owned file at either target path.
Revert removes only an exact project-generated setting; a locally changed file
is preserved for manual review.

## Firmware

The build does not install firmware. Keep MediaTek firmware current through the
distribution package manager and reboot if that package changes.

Fedora:

```bash
rpm -q linux-firmware
sudo dnf upgrade linux-firmware
```

Ubuntu:

```bash
dpkg-query -W linux-firmware
sudo apt update
sudo apt install --only-upgrade linux-firmware
```

Debian:

```bash
dpkg-query -W firmware-mediatek
sudo apt update
sudo apt install --only-upgrade firmware-mediatek
```

Arch Linux:

```bash
pacman -Q linux-firmware
sudo pacman -Syu linux-firmware
```

The MT7925 firmware files normally live under
`/lib/firmware/mediatek/mt7925/`.

## Status

Use deterministic terminal output for troubleshooting:

```bash
./mt76-check.sh --text
```

Exit status `0` means the custom `mt7925e` resolves from this project's overlay
and is loaded. Other states report stock resolution, an installed but unloaded
driver, stale or incomplete build metadata, or an unknown external module path.
Only paths below the current kernel's `kernel/` tree are classified as stock.

Inspect the real path selected by kmod for every module:

```bash
for module in mt76 mt76_connac_lib mt792x_lib mt7925_common mt7925e; do
  modinfo -n "$module"
done
```

With the custom stack installed, each path must be under the current kernel's
`updates/mt7925-wifi-patches/` directory.

## Revert

Run the portable wrapper from a normal shell:

```bash
./mt76-revert.sh
```

Use `./mt76-revert.sh --yes` for non-interactive confirmation. The helper
removes the current kernel's external overlay, runs `depmod`, verifies stock
resolution for all five modules, reloads `mt7925e`, and verifies the loaded
stack. It also removes unchanged project-generated optional settings while
preserving user-owned files.

## Desktop Status

The desktop entries use `Exec=mt76-check.sh`, so install the executable in the
user's `PATH` before installing either entry:

```bash
install -Dm755 mt76-check.sh "$HOME/.local/bin/mt76-check.sh"
install -Dm644 mt76-check.desktop \
  "$HOME/.config/autostart/mt76-check.desktop"
install -Dm644 mt76-status.desktop \
  "$HOME/.local/share/applications/mt76-status.desktop"
```

Confirm that `~/.local/bin` is in the graphical session's `PATH`. The checker
uses `notify-send` when available and otherwise prints the same status text.

Remove the entries with:

```bash
rm -f "$HOME/.config/autostart/mt76-check.desktop"
rm -f "$HOME/.local/share/applications/mt76-status.desktop"
rm -f "$HOME/.local/bin/mt76-check.sh"
```

## Development Checks

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

## License

MIT License. See [LICENSE](LICENSE).
