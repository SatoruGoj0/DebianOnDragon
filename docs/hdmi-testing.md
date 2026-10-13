# HDMI on kernel 7.2.0-debondragon-4: status and stability tests

## Status

| What | State | Evidence |
|---|---|---|
| HDMI video output, 1920x1080@60 | **Verified** | 83N3 + Samsung LS27D300G, kernel -4: `rate=540000, num_lanes=4` (HBR2 x4), link training #1 and #2 succeeded on the first attempt, no timeouts |
| Extended desktop under Hyprland | **Verified** | HDMI-A-1 at 0x0, eDP-1 at 1920x0; pointer and windows move between them |
| HDMI on at boot without sysfs commands | To test (T1, T2) | support 0.3.0, `DEBONDRAGON_HDMI=auto` |
| Long-running output | To test (T3) | |
| Reboot/shutdown with HDMI active | To test (T4): **reset before** | |
| Unplug/replug with active video | To test (T5): **reset before** | |

Converter: Parade PS176 (DPCD branch OUI 00-1C-F8, device ID `176GB0`),
DPCD 1.2, HBR2, 4 lanes. The fix is the DP lane orientation
(`data-lanes = <3 2 1 0>`), see `docs/board-notes.md`.

## How HDMI is switched on (support 0.3.0)

`DEBONDRAGON_HDMI` in `/etc/default/debondragon`:
- `auto` (default): HDMI on for kernels whose devicetree has the verified
  mapping (series 4 and later); `video=HDMI-A-1:d` for older kernels, whose
  mapping fails link training. Each series-4+ kernel also gets a
  "..., HDMI off" entry in GRUB's "DebOnDragon kernels" submenu.
- `off`: HDMI off everywhere. `on`: on everywhere (unsafe with -2/-3).

Hyprland needs nothing from DebOnDragon: monitor rules in your own
`~/.config/hypr/hyprland.lua` apply whenever HDMI-A-1 appears. Without a
rule for HDMI-A-1, the catch-all rule (`output = ""`, `preferred`, `auto`)
extends the desktop with the monitor's preferred mode.

## Logs that survive a reset

The persistent journal flushes ordinary kernel messages only every few
minutes, so for any step marked **reset before**, run this in a separate
terminal first; it writes the kernel log to disk every second:
```bash
mkdir -p ~/hdmi-test && dmesg -w > ~/hdmi-test/live-$(date +%H%M%S).log & while sleep 1; do sync ~/hdmi-test/live-*.log; done
```
After any boot, the previous boot's kernel log is also in the journal:
`sudo journalctl -k -b -1 > ~/hdmi-test/prev-boot.log`.

## Tests

Run them in order, one per boot where stated. Before each: save your work.
Stop at the first failure and send the logs; the next boot is the pinned
default kernel (-3), with HDMI off.

The test kernel is booted once with
```bash
sudo grub-reboot 'debondragon-kernels>debondragon-7.2.0-debondragon-4'
sudo reboot
```
which leaves the GRUB default unchanged.

### T1. Monitor connected before boot (one boot)

Cable plugged in and monitor on, then the one-time boot above.
```bash
uname -r; grep -c 'video=HDMI-A-1:d' /proc/cmdline     # -4, 0
cat /sys/class/drm/card0-HDMI-A-1/status                 # connected
hyprctl monitors | grep -E '^Monitor|@'                  # HDMI-A-1 1920x1080@60 at 0x0
journalctl -k -b | grep -E 'link training|Failed|timeout' | tail
```

### T2. Monitor connected after boot (one boot)

Cable unplugged, one-time boot, log in, then plug the cable in. Same
checks as T1.

### T3. Long run (same boot as T2)

Use both screens for 30 minutes: move windows and the pointer across,
play a video on the external one. Then:
```bash
journalctl -k -b | grep -cE 'vblank timeout|frame done timeout|Failed link training|BUG|lockup|hung'   # 0
```

### T4. Reboot with HDMI active (**reset before**: needs your go-ahead)

Start the live log above, `sync`, then a normal `sudo reboot` with the
monitor still showing the desktop. The reboot switches the output off
(teardown). Expected: a normal reboot into -3. Afterwards:
```bash
sudo journalctl -k -b -1 | tail -40 > ~/hdmi-test/t4-prev-boot.log
```

### T5. Unplug and replug with active video (**reset before**: needs your go-ahead)

Own boot of -4 (one-time boot), HDMI active. Start the live log, `sync`,
then unplug the cable **once**, wait 10 seconds, check the laptop still
responds, plug it in again **once**, wait 10 seconds:
```bash
cat /sys/class/drm/card0-HDMI-A-1/status; hyprctl monitors | grep -E '^Monitor|@'
grep -E 'link training|Failed|timeout|BUG|lockup' ~/hdmi-test/live-*.log | tail
```
No repeated plug cycles. If the laptop resets, the live log has
everything up to about a second before.

## Making -4 the default

Only after T1-T5 pass:
```bash
sudo sed -i 's/^DEBONDRAGON_DEFAULT_KERNEL=.*/DEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-4/' /etc/default/debondragon
sudo update-grub
```
-3 stays in the "DebOnDragon kernels" submenu (with HDMI off) for rollback,
and -4 has a "..., HDMI off" entry there too.
