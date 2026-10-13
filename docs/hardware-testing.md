# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the **new** kernel (`uname -r` shows `7.2.0-debondragon-3`
for the touchpad; the brightness and audio tests work on -2 with support 0.2.1). When done, collect everything with:

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

**v0.2.0 on hardware:** hot-plug and EDID work (`HDMI-A-1 connected`,
1920x1080), but DisplayPort link training to the HDMI converter fails
(`max v_level reached`, `Failed link training`), the screen stays black with
endless `vblank timeout`, and **unplugging the cable or disabling the output
resets the laptop** (no log, no pstore record).

Since support 0.2.1 HDMI is **off** (`video=HDMI-A-1:d` on the kernel
command line, `DEBONDRAGON_HDMI=off`). Leave it off. Kernel series 3 only
adds a read-only diagnostic, `/dev/drm_dp_auxN`, and lockup detectors; it
does **not** fix link training.

Do not set `DEBONDRAGON_HDMI=on` until a release says HDMI is ready to test.

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

**Result on the 83N3 (v0.2.0):** firmware version `0x03 0x00 0x18 0x01`,
thermal caps `0x00 0x00 0x00`, fan count 0. Commands 0x0E/0x42 aren't in
this EC's ACPI command map, so the protocol doesn't match and the check
refuses to enable the driver. **Keep it off**; the EC runs the fan itself.

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
microphones. The speaker amplifiers stay off. The card, codecs and DSP come
up on hardware. Up to support 0.2.0 the UCM profile never loaded (ALSA cuts
the card name to 31 characters); support 0.2.1 installs it under the card's
long name.

1. Check that the profile loads:
   ```bash
   alsaucm -c hw:0 list _verbs     # expect "HiFi"
   ```
2. Restart the sound server so it picks up the profile (or reboot):
   ```bash
   systemctl --user restart pulseaudio
   pactl list short sinks          # expect more than auto_null
   ```
3. Headphones: plug in headphones, select "Headphones", play something at
   **low volume first**.
4. Headset microphone (4-pole headset) and internal microphones:
   ```bash
   arecord -L | head
   arecord -f S16_LE -r 48000 -d 5 /tmp/mic.wav && aplay /tmp/mic.wav
   ```
5. Report what works, and send `debondragon-report`.

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
