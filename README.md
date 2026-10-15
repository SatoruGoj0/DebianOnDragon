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
| GPU acceleration (Adreno X1-45) | **Working** | unreleased (support 0.4.3) | The authenticated `qcdxkmsucpurwa.mbn` from Qualcomm display driver 31.0.133.1 is accepted; Vulkan enumerates Adreno X1-45 with Mesa Turnip |
| Hardware video decode (Qualcomm Iris) | **Partial** | unreleased (kernel series 10, support 0.4.3) | The 83N3 accepts the display driver's `qcvss8380_pa.mbn`; FFmpeg decoded 90-frame 1280x720 H.264 and HEVC samples and a 30-frame VP9 sample through `/dev/video2`. A 640x360 HEVC sample triggers an Iris firmware session error; see `TO-FIX.md` |
| Tailscale and Docker networking | **Working** | unreleased (kernel series 12) | Series 11 restored policy routing, nftables and NAT: Tailscale peer pings and Docker HTTPS egress are verified. Series 12 also supplies `xt_connmark` for Tailscale's reverse-path-filter workaround |
| Keyboard (I2C HID) | **Working** | v0.1.0 | Reported working |
| Touchscreen (ELAN 04F3:43B8) | **Working** | v0.1.0 | Reported working |
| Wi-Fi (WCN7850, ath12k) | **Working** | v0.1.0 | Reported working |
| Bluetooth (WCN7850) | **Working** | unreleased (kernel series 7) | Controller initialises and was confirmed operational alongside Wi-Fi on hardware |
| Touchpad (ELAN 04F3:327E) | **Working** | v0.3.0 | Verified on hardware with kernel 7.2.0-debondragon-3: interrupts on TLMM 19 (decoded from the DSDT; the CRD's TLMM 3 never fired), continuous pointer motion in libinput, normal use. `check-dtb.sh` keeps TLMM 19 / level-low / pull-up in every future build |
| Display brightness | **Partial** | v0.2.0 | Adjusting works on hardware. Started at minimum after every boot: systemd-backlight restored a stale 204/4095 (its 5% floor) because hard resets skip the save. support 0.2.1 saves the level once a minute when it changed and restores it exactly; without a saved level it starts at `DEBONDRAGON_MIN_BRIGHTNESS` (default 30%) |
| HDMI video output (1920x1080@60) | **Working** | v0.4.0 | Verified on hardware with kernel 7.2.0-debondragon-4 and a Samsung LS27D300G: DP link HBR2 x4, link training succeeds first time. Fix: DP lane orientation `data-lanes = <3 2 1 0>`. Converter: Parade PS176 |
| HDMI extended desktop (Hyprland) | **Working** | v0.4.0 | Verified: two monitors, pointer and windows move between them. Layout comes from your own Hyprland monitor rules |
| HDMI on at boot, hotplug, unplug/replug with active video, long runs | **Not yet verified** | v0.4.0 | support 0.3.0 switches HDMI on automatically for series-4 kernels (`DEBONDRAGON_HDMI=auto`); older kernels keep it off. Earlier kernels reset the laptop on unplug after failed training; tests in docs/hdmi-testing.md |
| Internal camera (USB 13d3:54bf) | **Working** | v0.2.0 | Reported working on hardware (UVC on usb_2 behind the PTN3222 repeater) |
| Fan / EC thermal control | **Unsupported, off** | — | `debondragon-ec-check` on hardware: version reads, but fan count and thermal capabilities return 0. Those commands (0x0E, 0x42) aren't in this EC's ACPI command map, so the `qcom-hamoa-ec` protocol doesn't match. Driver stays blacklisted; the EC controls the fan by itself |
| SoC temperature sensors | **Working** | v0.1.0 | CPU/GPU/PMIC zones read 37–40 °C on hardware |
| Headphones | **Working** | v0.4.0 | Kernel series 5, support 0.4.0, on the 83N3: the Headphones sink appears and playback works. Class-AB on the WCD9385. Needs the device ADSP firmware |
| Headset mic, internal mics | **Experimental** | v0.4.0 | The capture PCMs are in the profile (`hw:0,2` headset, `hw:0,3` internal). Not confirmed on hardware yet |
| Internal speakers | **Working** | v0.4.0 | Kernel series 5 on the 83N3: `speaker-test` plays Front Left. Front Right is silent on this unit in Debian and in Windows, so that speaker is a hardware fault. PA volume is capped at 0 dB; there is no active speaker protection. Keep the volume moderate |
| Mute, volume down, volume up (F1/F2/F3) | **Experimental** | v0.4.0 | The ITE keyboard reports these on a separate consumer-control evdev node, which the desktop does not open. `debondragon-volkeys` (support 0.4.1) handles them. Not confirmed on hardware yet |
| USB-A ports (2, multiport controller) | **Working** | v0.1.0 | Both ports used on hardware (mouse, install stick); USB 3 lanes enabled, speed not yet measured |
| USB-C ports (2, `usb_1_ss0/ss1`) | **Untested** | v0.1.0 | First port's controller (`usb_1_ss0`) comes up. The second (`usb_1_ss1`) never probes: the CRD puts its eUSB2 repeater in a PMIC (SPMI SID 0xa) that this laptop doesn't have (board notes). The CRD retimers don't answer, so role switching / alt mode don't work |
| Third USB controller (`usb_1_ss2`) | **N/A** | v0.2.0 | Disabled in this laptop's ACPI; its PHY carries HDMI |
| USB-C DisplayPort alt mode | **Unsupported** | — | Disabled: it blocked the internal display while ADSP firmware was missing |
| Battery status, charging info | **Working** | unreleased (kernel series 7) | Verified through PMIC GLINK: AC online, BYD L24B3PK2 present, status and energy reported; needs the 83N3 ADSP firmware from `debondragon-firmware` |
| SD card reader (BayHub, pcie5) | **Untested** | v0.1.0 | |
| Suspend / resume | **Untested** | — | |
| Fingerprint reader | **Unsupported** | — | |

## Remaining hardware (after v0.4.0)

The detailed, evidence-backed backlog is in [TO-FIX.md](TO-FIX.md).

- **Microphones**: headset mic and internal mics are in the profile and
  have not been confirmed on hardware.
- **Mute and volume keys**: support 0.4.1 listens for the keyboard's
  consumer-control events. Confirm with the steps in
  docs/hardware-testing.md.
- **HDMI audio** stays silent: the T14s topology has no DisplayPort graphs.
- **This unit's right speaker** is dead in Windows as well. That is a
  hardware fault, not a missing channel in the driver.
- **USB-C, second port**: its USB 2.0 repeater sits in an smb2360 at SPMI
  SID 0xa that this laptop doesn't have (probably SID 0xb instead,
  unverified); the CRD retimers don't answer, so role switching and DP alt
  mode don't work on either port.
- **EC fan reporting/control**: the EC doesn't speak the protocol of the
  upstream driver; driver stays off, the EC runs the fan itself.
- **Suspend/resume**: untested.

Device-signed firmware (audio/compute DSP, GPU zap shader and Iris video) is
signed for this machine and can't be redistributed. `debondragon-firmware`
copies it from your Windows partition. Support 0.4.3 deliberately installs
the Iris `_pa` image at the series-10 firmware path; the non-PA image is
rejected by this machine's secure monitor.

## Repository layout

| Path | What |
|---|---|
| `dts/` | Board devicetree: shared `.dtsi`, default board, and a `-speakers` file that is the same hardware (so an old `DEBONDRAGON_DTB` still boots) |
| `kernel/` | Config fragment, build script, config and module checks |
| `support/` | `debondragon-support` package: DTB hooks, GRUB entries, tools |
| `apps/earbuds/` | Earbuds app (GTK 4 + libadwaita) and its Waybar module: pair, connect, music/call mode, volume, microphone, battery |
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

The kernel source tag and every downloaded downstream patch are pinned (patch
downloads are also SHA-256 checked), so a clean checkout reproduces the same
kernel source and configuration. The ISO is repeatably buildable, but not
bit-for-bit reproducible indefinitely: Debian `trixie` and linux-firmware
`main` continue to move. Device-signed Lenovo firmware is deliberately absent
from both Git and the ISO; install it afterward with `debondragon-firmware`.

Every kernel build runs these checks and fails on a regression:

- `kernel/check-config.sh`: required options are set (built in where needed before the root filesystem mounts)
- `scripts/check-dtb.sh`: the compiled board DTB still states the hardware facts listed above
- `kernel/check-modules.sh`: every driver the DTB needs is in the package, and `depmod` resolves all module symbols
- `scripts/lint.sh`: syntax check and shellcheck for every script

## Background

This project replaces MacOnSnap, which explored native macOS on this laptop and
concluded it isn't feasible (no Qualcomm XNU port, no drivers, Apple licensing).
Linux has upstream Snapdragon X support, so here the work is a board port.
