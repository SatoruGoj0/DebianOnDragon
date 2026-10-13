# HDMI test for kernel 7.2.0-debondragon-4

Kernel series 4 changes one thing for HDMI: the lane orientation of the DP
PHY that feeds the HDMI converter (`data-lanes` `<0 1 2 3>` → `<3 2 1 0>`,
see `docs/board-notes.md`, "HDMI link training"). HDMI stays off by
default (`video=HDMI-A-1:d`). This test lifts that for **one running
session**; it changes nothing in GRUB or `/etc/default/debondragon`, and
the next boot is the pinned default kernel with HDMI off again.

Done on hardware so far (kernel -4, HDMI forced off): plugging and
unplugging the cable is safe, and the converter answers on
`/dev/drm_dp_aux1`: DPCD 1.2, HBR2, 4 lanes, TPS3, one HDMI downstream
port, branch OUI 00-1C-F8 (Parade) with device ID `176GB0` (PS176).

## How HDMI is enabled for one session

`video=HDMI-A-1:d` is applied once, when the connector is created
(`drm_connector.c`: `connector->force = mode->force`). Writing `detect` to
`/sys/class/drm/card0-HDMI-A-1/status` sets `connector->force` back to 0
and re-probes (`drm_sysfs.c`, `status_store`). If the status changes, the
probe helper queues a hot-plug event (msm enables the poll helper), and
Hyprland enables the monitor according to its monitor rules. That starts
DisplayPort link training. The force stays cleared until the next boot.

## What survives a hard reset

- `~/hdmi-test/dmesg-live.log`, written by `dmesg -w` and flushed to disk
  every second: everything up to about one second before a reset.
- The systemd journal is persistent, but it flushes debug-level kernel
  messages only every 5 minutes (`SyncIntervalSec`), so the DRM debug
  lines of the last minutes would be missing there.
- The kernel ring buffer itself is lost; there is no pstore backend.

## Steps

Run them in order; stop at the first one that doesn't match.

### 0. Starting point

Kernel -4 booted once (`grub-reboot`), default still pinned to -3, HDMI
cable **unplugged**, monitor on and set to its HDMI input. Save your work
and close other programs.

```bash
uname -r                                          # 7.2.0-debondragon-4
grep -o 'video=HDMI-A-1:d' /proc/cmdline
od -An -tu4 --endian=big /proc/device-tree/soc@0/phy@fdf000/ports/port@0/endpoint@0/data-lanes   # 3 2 1 0
cat /sys/class/drm/card0-HDMI-A-1/status          # disconnected
grep DEBONDRAGON_DEFAULT_KERNEL /etc/default/debondragon   # 7.2.0-debondragon-3
```

### 1. Hyprland rule for the external monitor

Extended desktop, HDMI to the right of the internal 1920x1200 panel,
1920x1080 at 60 Hz. The rule only applies when HDMI-A-1 appears; delete the
marked lines to remove it.
```bash
cat >> ~/.config/hypr/hyprland.lua <<'EOF'

-- DebOnDragon HDMI test (kernel -4): extended desktop right of eDP-1
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@60",
    position = "1920x0",
    scale    = 1,
})
-- end DebOnDragon HDMI test
EOF
hyprctl reload
hyprctl monitors | grep -E '^Monitor|@'           # eDP-1 unchanged
```

### 2. Start the log (second terminal, leave it running)

```bash
mkdir -p ~/hdmi-test
dmesg -w > ~/hdmi-test/dmesg-live.log & while sleep 1; do sync ~/hdmi-test/dmesg-live.log; done
```

### 3. DP debug logging, then plug in

In the first terminal:
```bash
echo 0x100 | sudo tee /sys/module/drm/parameters/debug
```
`0x100` is DRM's DisplayPort category: AUX transfers, link rate, lane
count and per-lane training status. Plug in the HDMI cable, wait 5 seconds:
```bash
cat /sys/class/drm/card0-HDMI-A-1/status          # still "disconnected" (forced)
```

### 4. Enable HDMI for this session

This is the active test: link training happens now.
```bash
sync
echo detect | sudo tee /sys/class/drm/card0-HDMI-A-1/status
```
Wait 15 seconds, then:
```bash
cat /sys/class/drm/card0-HDMI-A-1/status          # connected
cp /sys/class/drm/card0-HDMI-A-1/edid ~/hdmi-test/edid.bin
hyprctl monitors | grep -A2 HDMI-A-1              # 1920x1080@60 at 1920x0
grep -E 'link training|rate=|num_lanes|Failed|v_level|timeout' ~/hdmi-test/dmesg-live.log | tail -20
```

If `HDMI-A-1` doesn't appear in `hyprctl monitors` within 15 seconds,
nothing has been enabled: stop here, don't replug, and send the log.

### 5a. Picture on the monitor

- The desktop extends to the right; move the mouse across and drag a
  window onto the external monitor.
- `hyprctl monitors` shows `1920x1080@60` for HDMI-A-1.
- Leave it running for 5 minutes.

Then switch debug logging off and save the log:
```bash
echo 0 | sudo tee /sys/module/drm/parameters/debug
cp ~/hdmi-test/dmesg-live.log ~/hdmi-test/dmesg-success.log; sync
```
**Don't unplug or disable HDMI in this session.** Unplugging and disabling
an active output are the next, separate test. End this one with `sync`
and holding the power button for 10 seconds; the next boot is -3.

### 5b. Black screen, "Failed link training", or timeouts in the log

Stop activation attempts. **Don't unplug the cable and don't disable the
output** (that path reset the laptop before). Wait 5 seconds for the log to
reach the disk, then:
```bash
sync
```
and hold the power button for 10 seconds. The next boot is -3 with HDMI
forced off; with the laptop off, the cable can be removed safely. Send
`~/hdmi-test/dmesg-live.log`.

## Reading the log

- `link training #1 on phy 0 successful`, `#2 ... successful`,
  `num_lanes=4`: the orientation was the fault.
- 4-lane EQ fails, but a 2-lane retry passes clock recovery: orientation
  fixed, the rate is the problem (msm already falls back to lower rates and
  lanes by itself; a capped `link-frequencies` would be the next step).
- 2-lane retries fail with `max v_level reached` as before: orientation was
  not the cause; the `0x00202 AUX -> ...` lines show which lanes lock.

## Rollback

Every boot after the test boot is -3 (`DEBONDRAGON_DEFAULT_KERNEL`) with
HDMI forced off. To remove the Hyprland rule, delete the lines between the
two `DebOnDragon HDMI test` comments. To remove kernel -4 (while running
-3):
```bash
sudo apt remove linux-image-7.2.0-debondragon-4
```
