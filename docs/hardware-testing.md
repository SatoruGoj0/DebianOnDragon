# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the **new** kernel (`uname -r` shows `7.2.0-debondragon-2`
or later). When done, collect everything with:

```bash
sudo debondragon-report
```

It saves `debondragon-report-<date>.txt` to a plugged-in USB stick, or else to
your home folder. It contains the kernel log, input/USB/display/sound/thermal
state and the PMIC pin states. Attach it to an issue together with your test
results.

## Touchpad

**Bug in ≤ v0.1.4:** the touchpad interrupt line had no pull-up, so it floated
low and the driver read empty reports nonstop (`incomplete report (31/255)` in
`dmesg`). v0.2.0 enables the pull-up that the DSDT declares.

1. Move the pointer, tap, two-finger scroll, click.
2. Check:
   ```bash
   sudo dmesg | grep -c 'incomplete report'      # expect 0
   sudo cat /sys/kernel/debug/gpio | grep ' gpio3 '   # expect "in high ... pull up"
   ```

## Display brightness

v0.2.0 drives the backlight from pmk8550 PWM channel 0 (PMK8550 GPIO 5).

1. Press the brightness keys, or:
   ```bash
   ls /sys/class/backlight/
   cat /sys/class/backlight/backlight/max_brightness
   echo 1000 | sudo tee /sys/class/backlight/backlight/brightness   # dimmer
   echo 4000 | sudo tee /sys/class/backlight/backlight/brightness   # brighter
   ```
2. Report whether the screen actually changes, and whether very low values
   switch the backlight fully off.

If nothing changes, the PWM is still the wrong one. The report's PWM and PMIC
pin sections show what to try next.

## HDMI

1. Plug a monitor into the HDMI port, then check:
   ```bash
   for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status)"; done
   hyprctl monitors        # under Hyprland
   ```
   Expect an `HDMI-A-1` connector: `connected` with a monitor plugged in,
   `disconnected` without.
2. Report: whether the connector exists, whether it detects plugging, and
   whether a picture appears. If the connector shows up but there's no picture,
   the DP lane order may need swapping; say so.

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

## Fan and EC (opt-in)

The EC driver writes to the embedded controller when it loads, so it stays
blacklisted until the EC passes a **read-only** check:

```bash
sudo debondragon-ec-check
```

- `RESULT: the EC answers like the Hamoa EC`: the protocol matches. Enable
  the driver with `sudo debondragon-ec-check --enable`, then check
  `cat /sys/class/thermal/cooling_device*/type` for fan cooling devices.
- Any other result: leave it off and send the output.

Undo at any time with `sudo debondragon-ec-check --disable`.

Without the driver, the EC still runs the fan on its own. To check that the
fan responds to load, run a CPU load and listen:

```bash
for i in $(seq 8); do timeout 120 sh -c 'while :; do :; done' & done; wait
watch -n2 'cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -3'
```

## Thermal sensors

```bash
paste <(cat /sys/class/thermal/thermal_zone*/type) <(cat /sys/class/thermal/thermal_zone*/temp)
```
Temperatures are in millidegrees Celsius. Report whether the values are
plausible (roughly 30000–60000 at idle).

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

## Audio: headphones, headset mic, internal mics

The default devicetree enables the headset codec and the internal
microphones. The speaker amplifiers stay off. It needs the ADSP firmware, so
run `sudo debondragon-firmware` first if you haven't.

1. Check that the card and the DSP came up:
   ```bash
   cat /proc/asound/cards          # expect X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10
   ls /sys/bus/soundwire/devices/  # SoundWire devices found on the buses
   sudo dmesg | grep -iE 'q6apm|tplg|wcd938x|soundwire|remoteproc' | tail -20
   ```
2. Headphones: plug in headphones, select "Headphones" (pavucontrol or the
   Hyprland audio applet), play something at **low volume first**.
3. Headset microphone (4-pole headset) and internal microphones:
   ```bash
   arecord -L | head
   arecord -f S16_LE -r 48000 -d 5 /tmp/mic.wav && aplay /tmp/mic.wav
   ```
4. Report what works, and send `debondragon-report` (sound and SoundWire
   sections).

## Internal speakers (opt-in)

Linux has **no speaker protection** for these amplifiers. Overdriving them
can damage the speakers. The upstream profile limits the volume, but keep it
moderate anyway. Only try this after headphones work.

1. Switch to the speakers devicetree:
   ```bash
   sudo sed -i 's#^DEBONDRAGON_DTB=.*#DEBONDRAGON_DTB=qcom/x1p42100-lenovo-ideapad-slim3-15q8x10-speakers.dtb#' /etc/default/debondragon
   sudo debondragon-dtb-sync && sudo update-grub && sudo reboot
   ```
2. Check:
   ```bash
   cat /proc/asound/cards      # expect ...-SPK
   ls /sys/bus/soundwire/devices/   # expect the two amplifiers on swr0
   ```
   If the amplifiers aren't WSA884x, they don't bind and the speakers stay
   silent. That's harmless; report the SoundWire device list.
3. Play something at low volume.

Undo: set `DEBONDRAGON_DTB` back to `qcom/x1p42100-lenovo-ideapad-slim3-15q8x10.dtb`
and run the same two commands.
