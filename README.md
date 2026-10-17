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
| GPU acceleration (Adreno X1-45) | **Working** | unreleased (support 0.5.2) | The authenticated `qcdxkmsucpurwa.mbn` from Qualcomm display driver 31.0.133.1 is accepted; Vulkan enumerates Adreno X1-45 with Mesa Turnip |
| Hardware video decode (Qualcomm Iris) | **Partial** | unreleased (kernel series 10, support 0.5.2) | The 83N3 accepts the display driver's `qcvss8380_pa.mbn`; series 13 decoded all 90 frames of 1280x720 H.264 and HEVC through `/dev/video2` (VP9 was verified earlier). A 640x360 HEVC sample triggers an Iris firmware session error; see `TO-FIX.md` |
| Hardware video encode (Qualcomm Iris) | **Partial** | unreleased (kernel series 10, support 0.5.2) | On series 13, GStreamer encoded and verified 90-frame 1280x720 H.264 and HEVC streams through `/dev/video3`. Ubuntu FFmpeg 7.1.1's `h264_v4l2m2m` crashes in its userspace frame-copy path before the first frame; use GStreamer for now and see `TO-FIX.md` |
| Tailscale and Docker networking | **Working** | unreleased (kernel series 13) | Series 13 loads `xt_connmark`, Tailscale enables its connmark reverse-path-filter workaround without a health warning and reaches a peer, and a newly pulled Docker container has HTTPS egress |
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
| Fan / EC thermal control | **Experimental** | series 6 | Series 13 exposes the 75 °C CPU and 85 °C GPU passive trips on hardware. `qcom-hamoa-ec` stays blacklisted (wrong protocol; it would write debug mode). The opt-in `debondragon-fan` reporter is installed but not enabled. Support 0.5.1 wrote a fan-1 curve capped at 4000 rpm; at 73.8 °C the fan was still at 0 rpm. Support 0.5.2 reads that curve back. It does not write debug mode, the profile, or EC enable. Not yet confirmed to spin |
| SoC temperature sensors | **Working** | v0.1.0 | Zones read on hardware. Series 5, light use: every SoC zone 59–63 °C while the battery was 30 °C and the PMICs 37 °C |
| Headphones | **Partial** | v0.4.0 | Playback worked on series 5. On attach-mode series 11 and 13, the ADSP does not publish its `adsp_apps` GPR channel, so no sound card appears; see `TO-FIX.md` |
| Headset mic, internal mics | **Experimental** | v0.4.0 | The capture PCMs are in the profile (`hw:0,2` headset, `hw:0,3` internal). Not confirmed on hardware yet |
| Internal speakers | **Partial** | v0.4.0 | Kernel series 5 on the 83N3: `speaker-test` plays Front Left. Front Right is silent on this unit in Debian and in Windows, so that speaker is a hardware fault. PA volume is capped at 0 dB; there is no active speaker protection. Keep the volume moderate. Attach-mode series 11 and 13 expose no sound card at all, because the ADSP GPR audio channel is absent; see `TO-FIX.md` |
| Mute, volume down, volume up (F1/F2/F3) | **Experimental** | series 6 | On the 83N3 these keys arrive on the typing-keyboard node (`platform-a84000.i2c-event-kbd`, mode 660, `root:input`). Support 0.5.1 runs as root but treated logind session 2 (Hyprland on seat0) as inactive, because `ACTIVE=` in the seat file is the session id. Support 0.5.2 uses `loginctl show-seat seat0 -p ActiveSession`. Not confirmed on hardware yet |
| USB-A ports (2, multiport controller) | **Working** | v0.1.0 | Both ports used on hardware (mouse, install stick); USB 3 lanes enabled, speed not yet measured |
| USB-C ports (2, `usb_1_ss0/ss1`) | **Untested** | v0.1.0 | First port's controller (`usb_1_ss0`) comes up. The second (`usb_1_ss1`) never probes: the CRD puts its eUSB2 repeater in a PMIC (SPMI SID 0xa) that this laptop doesn't have (board notes). The CRD retimers don't answer, so role switching / alt mode don't work |
| Third USB controller (`usb_1_ss2`) | **N/A** | v0.2.0 | Disabled in this laptop's ACPI; its PHY carries HDMI |
| USB-C DisplayPort alt mode | **Unsupported** | — | Disabled: it blocked the internal display while ADSP firmware was missing |
| Battery status, charging info | **Working** | unreleased (kernel series 7) | Reconfirmed on series 13 through PMIC GLINK: battery present, state, percentage, voltage, energy, temperature and charge thresholds all reach UPower; needs the 83N3 ADSP firmware from `debondragon-firmware` |
| SD card reader (BayHub, pcie5) | **Untested** | v0.1.0 | |
| Suspend / resume | **Untested** | — | |
| Fingerprint reader | **Unsupported** | — | |

## Remaining hardware (after v0.4.0)

The detailed, evidence-backed backlog is in [TO-FIX.md](TO-FIX.md).

- **Microphones**: headset mic and internal mics are in the profile and
  have not been confirmed on hardware.
- **Mute and volume keys**: support 0.5.2 runs them as root and takes the
  uid from the seat's active session
  (`systemctl is-active debondragon-volkeys.service`). Confirm with the
  steps in docs/hardware-testing.md. Do not add your user to group `input`.
- **HDMI audio** stays silent: the T14s topology has no DisplayPort graphs.
- **This unit's right speaker** is dead in Windows as well. That is a
  hardware fault, not a missing channel in the driver.
- **USB-C, second port**: its USB 2.0 repeater sits in an smb2360 at SPMI
  SID 0xa that this laptop doesn't have (probably SID 0xb instead,
  unverified); the CRD retimers don't answer, so role switching and DP alt
  mode don't work on either port.
- **Fan**: series 6 throttles the CPUs at 75 °C and the GPU at 85 °C.
  Support 0.5.1's curve write was acknowledged and the fan was still
  stopped at 73.8 °C. Support 0.5.2 reads the curve back. Confirm it
  spins before treating this as done. `qcom-hamoa-ec` stays off.
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

On an x86-64 machine, the same build works in an emulated ARM64 container if
Docker has QEMU/binfmt support (Docker Desktop normally does):

```bash
docker run --rm --privileged --platform linux/arm64 \
  -v "$PWD:/src" -w /src debian:trixie ./build.sh
```

This is simple but slow because it compiles the kernel and compresses the ISO
under CPU emulation. The faster architecture-independent route is the
repository's **Build ISO** GitHub Actions workflow, which uses a native ARM64
runner and can be launched for any pushed branch with **Run workflow**. There
is not yet a native x86-to-ARM64 cross-build entrypoint.

Output in `out/`: the ISO, `linux-image-*.deb`, `linux-headers-*.deb`,
`debondragon-support_*_all.deb` and `SHA256SUMS`. `PACKAGES_ONLY=1` stops after
the packages (no ISO); `REBUILD_KERNEL=1` forces a kernel rebuild.

The kernel source tag and every downloaded downstream patch are pinned (patch
downloads are also SHA-256 checked), so a clean checkout reproduces the same
kernel source and configuration. The resulting packages are not promised to
be bit-for-bit identical because the build environment and timestamps are not
fully pinned. The ISO is repeatably buildable, but its Debian `trixie` packages,
base container and linux-firmware `main` continue to move. Device-signed Lenovo
firmware is deliberately absent from both Git and the ISO; install it afterward
with `debondragon-firmware`.

Every kernel build runs these checks and fails on a regression:

- `kernel/check-config.sh`: required options are set (built in where needed before the root filesystem mounts)
- `scripts/check-dtb.sh`: the compiled board DTB still states the hardware facts listed above
- `kernel/check-modules.sh`: every driver the DTB needs is in the package, and `depmod` resolves all module symbols
- `scripts/lint.sh`: syntax check and shellcheck for every script

## Background

This project replaces MacOnSnap, which explored native macOS on this laptop and
concluded it isn't feasible (no Qualcomm XNU port, no drivers, Apple licensing).
Linux has upstream Snapdragon X support, so here the work is a board port.
