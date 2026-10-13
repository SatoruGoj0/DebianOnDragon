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
| Touchpad (ELAN 04F3:327E) | **Experimental** | v0.2.0 | Malfunctioned up to v0.1.4: IRQ line had no pull-up and floated low (`incomplete report` floods). v0.2.0 adds the pull-up the DSDT declares |
| Display brightness | **Experimental** | v0.2.0 | v0.1.1–v0.1.4 drove an unconnected PWM. v0.2.0 uses pmk8550 PWM on PMK8550 GPIO 5, the pin the display owns in the DSDT and firmware leaves in PWM mode |
| HDMI | **Experimental** | v0.2.0 | DSDT: GPIO 126 is the display's hot-plug event, DP2 is a fixed-lane link, third USB-C controller disabled → DP2 → DP-to-HDMI bridge |
| Internal camera (USB 13d3:54bf) | **Experimental** | v0.2.0 | DSDT: camera on usb_2 behind an eUSB2 repeater (reset GPIO 7), same design as the Lenovo ThinkBook 16 |
| Fan / EC thermal control | **Experimental, off by default** | v0.2.0 | EC at i2c5 0x76 matches the upstream `qcom-hamoa-ec` write protocol; interrupt pin inferred. Driver blacklisted until `debondragon-ec-check` confirms it (see testing doc). The EC's own fan control works without it |
| SoC temperature sensors | **Experimental** | v0.1.0 | tsens built in; not yet checked on hardware |
| Headphones, headset mic, internal mics | **Experimental** | v0.2.0 | WCD9385 headset codec (reset TLMM 191 held by firmware, as on the CRD) + VA DMICs; own card name with packaged DSP topology and UCM profile. Needs the ADSP firmware (`debondragon-firmware`) |
| Internal speakers | **Experimental, opt-in** | v0.2.0 | Windows config: one amp group on SoundWire 0. Separate `-speakers` devicetree with 2× WSA884x (ThinkBook/T14s layout) and the upstream two-speaker UCM. Off by default: no speaker protection on Linux |
| USB-A ports (2, multiport controller) | **Working** | v0.1.0 | Both ports used on hardware (mouse, install stick); USB 3 lanes enabled, speed not yet measured |
| USB-C ports (2, `usb_1_ss0/ss1`) | **Untested** | v0.1.0 | Host controllers come up with SuperSpeed (boot log); orientation/role switching needs the ADSP firmware |
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
