# HDMI test for kernel 7.2.0-debondragon-4

Kernel series 4 changes one thing for HDMI: the lane orientation of the
DP PHY that feeds the HDMI converter (`data-lanes` `<0 1 2 3>` → `<3 2 1 0>`,
see `docs/board-notes.md`, "HDMI link training"). It is **not verified on
hardware**. HDMI stays off by default (`video=HDMI-A-1:d`); this test lifts
that for one boot only, from a running session, and never touches GRUB or
`/etc/default/debondragon`.

Do the steps in order and stop at the first one that doesn't match. Each
step says what to send back.

## 0. Before you start

- `debondragon-support` 0.2.1, kernel -3 working and pinned as default:
  ```bash
  grep DEBONDRAGON_DEFAULT_KERNEL /etc/default/debondragon   # =7.2.0-debondragon-3
  ```
- Install -4 beside -3 (`docs/kernel-upgrade.md`, "Test a new kernel
  once"), then boot it once:
  ```bash
  sudo grub-reboot 'debondragon-kernels>debondragon-7.2.0-debondragon-4'
  sudo reboot
  ```
  HDMI cable **unplugged** for this boot.

## 1. Kernel -4 without HDMI (regression check)

```bash
uname -r                                   # 7.2.0-debondragon-4
cat /proc/cmdline | grep -o 'video=HDMI-A-1:d'
grep hid-over-i2c /proc/interrupts         # touchpad on msmgpio 19, counting
```
Check the internal screen, brightness keys, touchpad, keyboard, Wi-Fi and
camera as you normally use them. If anything regressed, stop here and reboot
(the next boot is -3).

## 2. Plug in the monitor while HDMI is still forced off

Save your work first. Plug the HDMI cable in, wait 5 seconds, then:
```bash
cat /sys/class/drm/card0-HDMI-A-1/status   # still "disconnected" (forced off)
sudo dmesg | tail -20
```
Optional, read-only: the converter's capabilities. This may fail with
"Input/output error" while the connector is forced off; that's fine.
```bash
sudo dd if=/dev/drm_dp_aux1 bs=1 count=16 2>/dev/null | od -An -tx1
sudo dd if=/dev/drm_dp_aux1 bs=1 skip=$((0x500)) count=16 2>/dev/null | od -An -tx1
```
`/dev/drm_dp_aux1` is the HDMI path: it belongs to DP controller
`ae9a000` (dp2), the only DP controller wired to the HDMI converter.

Send the output. If the laptop resets when you plug in, stop here.

## 3. Enable HDMI for this boot, with full DP logging

Close other programs and save everything. Open a second terminal and
start a log that is written to disk as it goes:
```bash
sudo dmesg -w | tee ~/hdmi-test-4.log
```
In the first terminal:
```bash
sync
echo 0x104 | sudo tee /sys/module/drm/parameters/debug
echo detect | sudo tee /sys/class/drm/card0-HDMI-A-1/status
```
Hyprland then enables the monitor (your monitor rule is "preferred,
auto"), which starts DisplayPort link training. Wait 15 seconds.

### 3a. Picture on the monitor

```bash
hyprctl monitors | grep -A3 HDMI          # 1920x1080@60
grep -E "link training|rate=|num_lanes" ~/hdmi-test-4.log | tail
```
Leave it running for a few minutes (move a window onto it). Then turn the
debug logging off again and send `~/hdmi-test-4.log`:
```bash
echo 0 | sudo tee /sys/module/drm/parameters/debug
```
**Don't unplug or disable HDMI yet.** Reboot normally when done. Unplug and
disable are a separate test once training is confirmed.

### 3b. Still black, or "Failed link training" in the log

Don't unplug the cable and don't disable the output in Hyprland: that is
the path that reset the laptop before. Instead:
```bash
sync
```
then hold the power button for 10 seconds. The next boot is -3 with HDMI
off. Send `~/hdmi-test-4.log` (it was written while the test ran).

## What the log tells us

- `link training #1 ... successful` and `#2 ... successful` with
  `num_lanes=4`: the orientation was the fault.
- 4-lane EQ fails but the 2-lane retry now passes clock recovery: the
  orientation is fixed and the remaining problem is the link rate (next
  experiment: cap `link-frequencies`).
- The same pattern as before (2-lane retries fail with `max v_level
  reached`): orientation was not the cause; the per-lane status in the log
  shows which lanes lock.
- `0x00500 AUX -> ...` lines: the converter's IEEE OUI (vendor) and device
  ID string, which identify the chip.

## Rollback

Every boot after the test boot is -3 (`DEBONDRAGON_DEFAULT_KERNEL`), with
HDMI forced off. Nothing in this test changes GRUB or `/etc/default`. To
remove -4 (while running -3):
```bash
sudo apt remove linux-image-7.2.0-debondragon-4
```
