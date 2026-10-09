# DebOnDragon

Debian 13 (trixie, arm64) for the **Lenovo IdeaPad Slim 3 15Q8X10** (machine
type 83N3) with the **Snapdragon X X1-26-100** (Qualcomm Oryon, "Purwa").

The project builds a live + installer ISO with:

- a mainline Linux kernel (v7.2) built with arm64 `defconfig` and a small fragment
- a devicetree for this exact laptop (`dts/x1p42100-lenovo-ideapad-slim3-15q8x10.dts`)
- the redistributable firmware it needs (Wi-Fi, Bluetooth, GPU generics)
- an XFCE live desktop with the Calamares installer
- GRUB set up to load the devicetree on the live system and after installing

GitHub Actions builds the ISO on every push to `main` and publishes it as a release
on `v*` tags. **To install, follow [docs/install.md](docs/install.md).**

## Status

This is a first, untested-on-hardware release. The devicetree is derived from
this laptop's own ACPI tables (see [docs/board-notes.md](docs/board-notes.md)),
but nothing has been booted on the 83N3 yet.

| Hardware | Expected | Notes |
|---|---|---|
| Boot, CPU (8 cores), RAM | should work | upstream Purwa support |
| Keyboard, touchpad, touchscreen | should work | I2C buses and GPIOs mapped from the DSDT |
| Display (internal) | should work | eDP; brightness control may not work yet |
| NVMe SSD | should work | pcie6a |
| USB-A port | should work | use it for the install USB stick |
| Wi-Fi / Bluetooth (WCN7850) | likely | ath12k firmware is on the ISO |
| USB-C, battery status, charging info | needs firmware | run `debondragon-firmware` |
| GPU acceleration | needs firmware | run `debondragon-firmware` |
| SD card reader (BayHub, pcie5) | maybe | |
| Audio | **off** | disabled on purpose until the speaker layout is known |
| Webcam, suspend, HDMI | unknown | |

Device-signed firmware (audio/compute DSP, GPU zap shader) is signed for this
machine and can't be redistributed. The ISO ships a helper,
`debondragon-firmware`, that copies it from your Windows partition.

## Repository layout

| Path | What |
|---|---|
| `dts/` | Board devicetree |
| `kernel/` | Kernel config fragment and build script |
| `iso/` | Root filesystem, firmware, GRUB and ISO assembly; `iso/overlay/` is copied into the image |
| `windows/Export-Firmware.ps1` | Copies device firmware out of Windows (read-only) |
| `scripts/` | ACPI/DSDT analysis helpers used to write the devicetree |
| `hardware-reports/` | Data collected from this laptop (no serial numbers) |
| `build.sh` | Builds everything; needs arm64 Debian 13 as root |

## Building locally

Any arm64 Debian 13 environment works, including WSL on the laptop itself or Docker:

```bash
docker run --rm --privileged -v "$PWD:/src" -w /src debian:trixie ./build.sh
```

The ISO lands in `out/`. The kernel build takes the longest; rerunning reuses
`work/kernel-debs` unless `REBUILD_KERNEL=1`.

## Background

This project replaces MacOnSnap, which explored native macOS on this laptop and
concluded it isn't feasible (no Qualcomm XNU port, no drivers, Apple licensing).
Linux has upstream Snapdragon X support, so here the work is a board port.
