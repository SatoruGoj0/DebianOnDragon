# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the kernel that implements it (`uname -r`). The touchpad
test is series 3, HDMI is series 4, and audio is series 5. Volume keys
need support 0.4.1. Fan trips need kernel series 6; the fan reporter
needs support 0.5.0. When done, collect everything with:

```bash
sudo debondragon-report
```

It saves `debondragon-report-<date>.txt` to a plugged-in USB stick, or else to
your home folder. It contains the kernel log, input/USB/display/sound/thermal
state and the PMIC pin states. Attach it to an issue together with your test
results.

## Touchpad

**Working since v0.3.0 (verified on hardware).** Up to v0.2.0 the
interrupt was on the CRD's TLMM 3, which never fired (`device did not ack
reset within 1000 ms`, no input). Decoding the DSDT (`docs/board-notes.md`)
put it on **TLMM 19**; on `7.2.0-debondragon-3` that line counts interrupts
and libinput reports continuous pointer motion. Use these checks if the
touchpad stops working after an upgrade.

On `7.2.0-debondragon-3`:
1. Check the boot log and the interrupt line:
   ```bash
   sudo dmesg | grep -E '0-0015|04F3:327E'      # no "did not ack reset"
   grep hid-over-i2c /proc/interrupts            # touchpad line: "msmgpio 19"
   sudo cat /sys/kernel/debug/gpio | grep ' gpio19 '   # "in high ... pull up"
   ```
2. Move a finger on the touchpad, then read `/proc/interrupts` again: the
   `msmgpio 19` count must have gone up.
3. Move the pointer, tap, two-finger scroll, click.

If the count stays at 0, send the report.

## Display brightness

Adjusting brightness works on hardware (pmk8550 PWM channel 0). Up to
support 0.2.0 it started near minimum after every boot (systemd-backlight's
5% floor after hard resets). With support 0.2.1:

1. Set a brightness you like, wait 1 minute, reboot normally. It must come
   back at the same level.
2. Check the saved level and the timer:
   ```bash
   cat /var/lib/debondragon/backlight-backlight
   systemctl list-timers debondragon-backlight-save.timer
   journalctl -b -u debondragon-backlight.service
   ```
3. A very low level set on purpose must also come back as is.

## HDMI

**Working since v0.4.0 (verified):** video at 1920x1080@60 and the
extended desktop, on kernel `7.2.0-debondragon-4`. With support 0.3.0
(`DEBONDRAGON_HDMI=auto`) HDMI is on for -4 and off for older kernels.
Still to verify: HDMI at boot and hotplug with the automatic setting, long
runs, reboot and unplug/replug with active video. Those tests, with
crash-safe logging, are in **docs/hdmi-testing.md**.

## Camera

1. Check that the camera enumerates:
   ```bash
   lsusb | grep -i 13d3:54bf
   v4l2-ctl --list-devices        # package v4l-utils
   ```
2. Show a picture (package `ffmpeg`, or any camera app):
   ```bash
   ffplay /dev/video0
   ```
3. If `lsusb` doesn't list it, send the report: its USB and `dmesg` sections
   show whether the eUSB2 repeater at i2c5 0x4b answered.

## Fan and thermals (kernel series 6, support 0.5.0)

**What series 5 did.** Light use, laptop warm to the touch: every SoC zone
(cpu0/cpu1 clusters, cpuss, gpuss, nsp, aoss, mem, video, camera) read
59.4–62.6 °C, the battery 30.2 °C, and the pm8550/pmc8380 zones 37 °C.
The SoC zones matching each other means the fan is off or barely moving.
The EC's own thermistors sit with the battery and the PMICs, not on the
die. Windows repeatedly sends die temperature to the EC (DSDT "Temp to
EC", I2C register 0x20). Linux was not sending it, so the fan curve never
saw 60 °C. The CPU zones also had no passive trip, only a 115 °C critical
shutdown.

**Do not enable `qcom-hamoa-ec`.** `debondragon-ec-check` on this machine
reads firmware `0x03 0x00 0x18 0x01` and thermal caps `0x00 0x00 0x00`
(fan count 0). Those commands are not this EC's map. The driver would
write debug mode (register 0x30) on probe. Leave it blacklisted.

Series 6 throttles on its own, with no EC write: CPU and CPUSS passive
trips at 75 °C, GPU passive trip lowered from 95 °C to 85 °C. Critical
trips stay at 115 °C. Confirm the trips after booting series 6:

```bash
uname -r    # 7.2.0-debondragon-6
grep . /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/trip_point_*_temp /sys/class/thermal/thermal_zone*/trip_point_*_type | grep -E 'passive|75000|85000'
```

**Fan reporter (opt-in, writes the EC).** It sends only the temperature
report (register 0x20, decidegrees Celsius, sensors 0x01 CPU-aggregate,
0x02 the CPU zone, 0x03 the GPU zone) and, around suspend, modern-standby
status (register 0x23). It does not set RPM, replace the fan curve, or
clear any EC failsafe. The EC decides the speed.

Read first. This writes nothing:

```bash
sudo debondragon-fan status
```

Then turn reporting on and watch the fan. Stop the load with Ctrl-C; leave
the reporter running.

```bash
sudo debondragon-fan enable
for i in $(seq 8); do timeout 90 sh -c 'while :; do :; done' & done
watch -n2 'sudo debondragon-fan status'
```

Send back: `status` before enable (fan RPM at the 60 °C soak), `status`
after a minute of load (RPM and the hottest zone), and whether you can
hear the fan. Expected if the report is in the unit the EC's curve uses:
RPM rises from 0 once the die is warm, and the SoC stops sitting at 60 °C
with the fan stopped. Not confirmed yet.

**Safety.** After `enable`, do not `systemctl stop debondragon-fan` and
walk away. If temperature reports stop for more than a couple of minutes,
this EC can power the machine off; that is its failsafe for a hung OS,
and it must stay. Suspend is handled (the EC is told first). To turn
reporting off:

```bash
sudo debondragon-fan disable
sudo reboot
```

`disable` tells the EC the OS is suspended before it stops the updates.
Reboot so that notice does not linger. If the fan never moves after
`enable`, disable it and send the `status` output. Do not try other I2C
writes; a wrong temperature unit can look like an overtemp.

## Thermal sensors

```bash
paste <(cat /sys/class/thermal/thermal_zone*/type) <(cat /sys/class/thermal/thermal_zone*/temp)
```
Temperatures are in millidegrees Celsius. On series 5 with the fan not
tracking the die, SoC zones near 60000 at light use and PMIC/battery
zones near 30000–37000 are the reading that prompted the series 6 trips.

## Bluetooth

```bash
bluetoothctl power on; bluetoothctl scan on
```
Pair a device and report whether it works.

## Untested items

These are compiled but nobody has tested them yet. Any results help:

- USB-C data on both ports (plug in a USB-C stick, both orientations), and
  USB-A speed (`lsusb -t` shows 5000M for a USB 3 stick)
- battery status (`upower -d`)
- SD card reader
- suspend: `systemctl suspend`, then wake with the power button

## Audio: speakers and headphones

Verified on the 83N3 with kernel `7.2.0-debondragon-5` and
`debondragon-support` 0.4.0: the card and the HiFi profile come up,
PulseAudio lists Speaker and Headphones, and `speaker-test` plays Front
Left. Front Right is silent on this unit in Debian and in Windows, so
that speaker is a hardware fault.

Support 0.4.1 reloads PulseAudio when the playback devices appear, so the
sinks should be there after boot without
`systemctl --user restart pulseaudio`. The PA volume is capped at 0 dB.
There is still no active speaker protection. Keep the volume moderate.

The ADSP firmware is signed for this machine and is not in the image:

```bash
sudo debondragon-firmware
sudo debondragon-firmware --help
```

A Windows partition that is already mounted is picked up. You can still
pass the FileRepository folder, or a folder from
`windows/Export-Firmware.ps1`.

1. After a normal boot, without restarting PulseAudio:
   ```bash
   cat /proc/asound/cards
   alsaucm -c hw:0 list _verbs     # HiFi
   pactl list short sinks          # Speaker, and Headphones when the jack is in
   ```
   If the only sink is `auto_null`, wait a few seconds and list again
   (the card can finish probing just after login). If it stays
   `auto_null`, `systemctl --user restart pulseaudio` is the workaround;
   report `dmesg` from that boot.
2. Speakers, moderate volume. Front Left should play. Front Right on this
   unit stays silent:
   ```bash
   speaker-test -D hw:0,1 -c 2 -t wav
   ```
3. Headphones: plug in a 3-pole jack. PulseAudio switches to Headphones.
   `hw:0,0` is the headphone PCM.

## Microphones (not confirmed yet)

```bash
arecord -D hw:0,2 -f S16_LE -r 48000 -d 5 /tmp/headset.wav && aplay /tmp/headset.wav
arecord -D hw:0,3 -f S16_LE -r 48000 -d 5 /tmp/mic.wav && aplay /tmp/mic.wav
```

`hw:0,2` is the headset mic (4-pole jack), `hw:0,3` the internal mics.
HDMI audio stays silent.

## Mute and volume keys

F1, F2 and F3 are mute, volume down and volume up. The keyboard sends
them as consumer-control keys (`KEY_MUTE`, `KEY_VOLUMEDOWN`,
`KEY_VOLUMEUP`) on their own input device, separate from the typing
keys. Support 0.4.1 runs `debondragon-volkeys`, which calls `pactl` for
those keys. Log out and back in (or reboot) after installing 0.4.1.

1. The service is running:
   ```bash
   systemctl --user is-active debondragon-volkeys.service
   ```
2. Press F1, F2 and F3 with a tune playing. F1 mutes, F2 lowers the
   volume, F3 raises it, in steps of 5%. The panel icon should follow.
3. If nothing changes, see which event the key actually produces:
   ```bash
   sudo libinput debug-events
   ```
   A working key prints `KEY_MUTE`, `KEY_VOLUMEDOWN` or `KEY_VOLUMEUP`.
   `KEY_F1` / `KEY_F2` / `KEY_F3` means the keyboard is in function-key
   mode (Fn+Esc toggles Fn Lock; the Esc LED shows it). Send the
   `libinput` lines and `debondragon-report`.
