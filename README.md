# DebOnDragon

Debian 13 (trixie, arm64) for the **Lenovo IdeaPad Slim 3 15Q8X10** (machine
type 83N3) with the **Snapdragon X X1-26-100** (Qualcomm Oryon, "Purwa").

The project builds:

- a mainline Linux kernel (v7.2, arm64 `defconfig` plus a small fragment) as Debian packages
- a devicetree for this exact laptop (`dts/x1p42100-lenovo-ideapad-slim3-15q8x10.dts`),
  derived from the laptop's own ACPI tables and from hardware logs
- `debondragon-support`, a package with the boot integration and diagnostic tools
- a live + installer ISO (XFCE, Calamares)

GitHub Actions builds everything on each push to `main` and publishes a release on `v*` tags.

- New install: [docs/install.md](docs/install.md)
- **Update the kernel on an installed system** (no reinstall) and roll back:
  [docs/kernel-upgrade.md](docs/kernel-upgrade.md)
- Test the hardware and report results: [docs/hardware-testing.md](docs/hardware-testing.md)

## Hardware support

**Status** is what has been seen working on a real 83N3. **Since** is the
release that implements it. Something that only compiles is never listed as
Working.

| Status | Meaning |
|---|---|
| **Working** | Verified on the 83N3 hardware |
| **Partial** | Works on hardware with known gaps |
| **Not working** | Tested on hardware and broken |
| **Experimental** | Implemented and compiled from hardware evidence, **not yet tested on hardware** |
| **Unsupported** | Not implemented (or deliberately disabled) |

| Component | Status | Since | Evidence / notes |
|---|---|---|---|
| Boot (GRUB, kernel, initramfs, NVMe root) | **Working** | v0.1.4 | Installed system boots; GRUB entry created from Windows (Linux can't write UEFI variables on this machine) |
| Internal display (eDP, 1920x1200) | **Working** | v0.1.3 | msm DRM drives the panel (`eDP-1 connected`) |
| GPU acceleration (Adreno X1-45) | **Working** | v0.1.0 | Reported working under Hyprland; needs `debondragon-firmware` |
| Keyboard (I2C HID) | **Working** | v0.1.0 | Reported working |
| Touchscreen (ELAN 04F3:43B8) | **Working** | v0.1.0 | Reported working |
| Wi-Fi (WCN7850, ath12k) | **Working** | v0.1.0 | Reported working |
| Bluetooth (WCN7850) | **Partial** | v0.1.0 | Firmware loads and the controller initialises (boot log); pairing not yet tested |
| Touchpad (ELAN 04F3:327E) | **Working** | v0.3.0 | Verified on hardware with kernel 7.2.0-debondragon-3: interrupts on TLMM 19 (decoded from the DSDT; the CRD's TLMM 3 never fired), continuous pointer motion in libinput, normal use. `check-dtb.sh` keeps TLMM 19 / level-low / pull-up in every future build |
| Display brightness | **Partial** | v0.2.0 | Adjusting works on hardware. Started at minimum after every boot: systemd-backlight restored a stale 204/4095 (its 5% floor) because hard resets skip the save. support 0.2.1 saves the level once a minute when it changed and restores it exactly; without a saved level it starts at `DEBONDRAGON_MIN_BRIGHTNESS` (default 30%) |
| HDMI | **Not working, off by default** | — | v0.2.0 on hardware: hot-plug and EDID work, but DisplayPort link training to the HDMI converter fails (black screen, endless vblank timeouts), and unplugging or disabling the output resets the laptop. support 0.2.1 disables the connector (`video=HDMI-A-1:d`, `DEBONDRAGON_HDMI`) until this is fixed |
| Internal camera (USB 13d3:54bf) | **Working** | v0.2.0 | Reported working on hardware (UVC on usb_2 behind the PTN3222 repeater) |
| Fan / EC thermal control | **Unsupported, off** | — | `debondragon-ec-check` on hardware: version reads, but fan count and thermal capabilities return 0. Those commands (0x0E, 0x42) aren't in this EC's ACPI command map, so the `qcom-hamoa-ec` protocol doesn't match. Driver stays blacklisted; the EC controls the fan by itself |
| SoC temperature sensors | **Working** | v0.1.0 | CPU/GPU/PMIC zones read 37–40 °C on hardware |
| Headphones, headset mic, internal mics | **Experimental** | v0.3.0 | Card, codecs and DSP come up on hardware. v0.2.0's UCM profile never loaded (ALSA cuts the card name to 31 characters); support 0.2.1 installs it under the card's long name. On hardware the profile now loads and PulseAudio offers a Headphones sink instead of `auto_null`. Sound output not yet tested |
| Internal speakers | **Experimental, opt-in** | v0.2.0 | Windows config: one amp group on SoundWire 0. Separate `-speakers` devicetree with 2× WSA884x (ThinkBook/T14s layout) and the upstream two-speaker UCM. Off by default: no speaker protection on Linux |
| USB-A ports (2, multiport controller) | **Working** | v0.1.0 | Both ports used on hardware (mouse, install stick); USB 3 lanes enabled, speed not yet measured |
| USB-C ports (2, `usb_1_ss0/ss1`) | **Untested** | v0.1.0 | First port's controller (`usb_1_ss0`) comes up. The second (`usb_1_ss1`) never probes: the CRD puts its eUSB2 repeater in a PMIC (SPMI SID 0xa) that this laptop doesn't have (board notes). The CRD retimers don't answer, so role switching / alt mode don't work |
| Third USB controller (`usb_1_ss2`) | **N/A** | v0.2.0 | Disabled in this laptop's ACPI; its PHY carries HDMI |
| USB-C DisplayPort alt mode | **Unsupported** | — | Disabled: it blocked the internal display while ADSP firmware was missing |
| Battery status, charging info | **Untested** | v0.1.0 | Need the ADSP firmware from `debondragon-firmware` |
| SD card reader (BayHub, pcie5) | **Untested** | v0.1.0 | |
| Suspend / resume | **Untested** | — | |
| Fingerprint reader | **Unsupported** | — | |

Device-signed firmware (audio/compute DSP, GPU zap shader) is signed for this
machine and can't be redistributed. `debondragon-firmware` copies it from your
Windows partition.

## Repository layout

| Path | What |
|---|---|
| `dts/` | Board devicetree: shared `.dtsi`, default board, opt-in `-speakers` board |
| `kernel/` | Config fragment, build script, config and module checks |
| `support/` | `debondragon-support` package: DTB hooks, GRUB entries, tools |
| `iso/` | Root filesystem, firmware, GRUB and ISO assembly |
| `windows/` | Windows-side helpers: export firmware, create the GRUB boot entry |
| `scripts/` | ACPI/DSDT analysis, DTB assertions, lint |
| `hardware-reports/` | Data collected from this laptop (no serial numbers) |
| `docs/board-notes.md` | Where every devicetree choice comes from |
| `build.sh` | Builds everything; needs arm64 Debian 13 as root |

## Building

Any arm64 Debian 13 environment works, including WSL on the laptop itself or Docker:

```bash
docker run --rm --privileged -v "$PWD:/src" -w /src debian:trixie ./build.sh
```

Output in `out/`: the ISO, `linux-image-*.deb`, `linux-headers-*.deb`,
`debondragon-support_*_all.deb` and `SHA256SUMS`. `PACKAGES_ONLY=1` stops after
the packages (no ISO); `REBUILD_KERNEL=1` forces a kernel rebuild.

Every kernel build runs these checks and fails on a regression:

- `kernel/check-config.sh`: required options are set (built in where needed before the root filesystem mounts)
- `scripts/check-dtb.sh`: the compiled board DTB still states the hardware facts listed above
- `kernel/check-modules.sh`: every driver the DTB needs is in the package, and `depmod` resolves all module symbols
- `scripts/lint.sh`: syntax check and shellcheck for every script

## Background

This project replaces MacOnSnap, which explored native macOS on this laptop and
concluded it isn't feasible (no Qualcomm XNU port, no drivers, Apple licensing).
Linux has upstream Snapdragon X support, so here the work is a board port.
