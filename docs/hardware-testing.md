# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the kernel that implements it (`uname -r`). The touchpad
test is series 3, HDMI is series 4, the battery/audio tests use series 7,
and hardware video decode uses series 10 with support 0.4.2. When done,
collect everything with:

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

## Battery and AC

**Working on kernel series 7 (verified on hardware).** Install the matching
83N3 firmware with `sudo debondragon-firmware`, reboot, and check:

```bash
upower -d
for d in /sys/class/power_supply/*; do
    echo "$(basename "$d")"; grep -H . "$d"/{present,status,online,energy_now,energy_full,voltage_now} 2>/dev/null
done
```

The test machine reported AC online and a present BYD L24B3PK2 battery with
status, voltage, current energy and full energy. If the devices are absent,
check `systemctl status pd-mapper` and the `remoteproc`/`pmic_glink` lines in
`sudo dmesg`.

## Hardware video decoding

Needs kernel `7.2.0-debondragon-10` (or later), support 0.4.2, the Lenovo
`qcvss8380.mbn` installed by `debondragon-firmware`, `v4l-utils`, and `ffmpeg`.
The older `7.2.2-ideapad-iris1+` experiment selected the generic
`qcom/vpu/vpu30_p1_s7.mbn`; the secure monitor rejected it with error `-22`.

1. Confirm the Iris driver loaded without a firmware/authentication error and
   identify its V4L2 mem2mem nodes:
   ```bash
   sudo dmesg | grep -Ei 'qcom-iris|video-codec|qcvss|videocc'
   v4l2-ctl --list-devices
   for d in /dev/video*; do echo "=== $d ==="; v4l2-ctl -d "$d" --all 2>/dev/null | head -20; done
   ```
   The integrated UVC camera is not the decoder. Iris should appear as a
   separate Qualcomm codec with both compressed input and raw capture formats.
2. Decode a local H.264 file explicitly through V4L2 mem2mem:
   ```bash
   ffmpeg -benchmark -c:v h264_v4l2m2m -i sample-h264.mp4 -an -f null -
   ```
   Repeat with `hevc_v4l2m2m` or `vp9_v4l2m2m` and a matching sample. The log
   must name the V4L2 mem2mem decoder and finish without falling back to the
   software decoder.
3. Send `sudo dmesg` plus the exact FFmpeg output if firmware authentication,
   format negotiation, or decode fails. Browser acceleration comes only after
   this direct test passes.

## Untested items

These are compiled but nobody has tested them yet. Any results help:

- USB-C data on both ports (plug in a USB-C stick, both orientations), and
  USB-A speed (`lsusb -t` shows 5000M for a USB 3 stick)
- SD card reader
- suspend: `systemctl suspend`, then wake with the power button

## Audio: speakers, headphones, microphones

Needs kernel `7.2.0-debondragon-7` (or later) and `debondragon-support`
0.4.2. Speakers, the headphone jack and the microphones are on the default
devicetree. Install the packages beside the kernel you already trust and
boot series 7 once (`docs/kernel-upgrade.md`, "Test a new kernel once").
Series 4 stays the rollback: it has headphones and mics, and no speaker
amps.

The PA volume is capped at 0 dB. There is still no active speaker
protection. Start at a moderate volume.

The ADSP firmware is signed for this machine and is not in the image. Copy
it before expecting a sound card, then reboot:

```bash
sudo debondragon-firmware
```

Or, from Windows, `windows/Export-Firmware.ps1` onto a stick and
`sudo debondragon-firmware /media/$USER/<stick>/debondragon-firmware`.

1. The card and the profile:
   ```bash
   cat /proc/asound/cards          # a card, not an empty file
   alsaucm -c hw:0 list _verbs     # HiFi
   ls /sys/bus/soundwire/devices/  # two WSA8845 on swr0, plus the WCD9385
   systemctl --user restart pulseaudio
   pactl list short sinks          # Speaker; Headphones appears with a jack
   ```
2. Speakers, moderate volume:
   ```bash
   speaker-test -D hw:0,1 -c 2 -t wav
   ```
   `hw:0,1` is the speaker PCM. `hw:0,0` is the headphone jack.
3. Headphones: plug in a 3-pole jack. PulseAudio should switch to
   Headphones (`Headphone Jack`). Play at moderate volume.
4. Headset microphone (4-pole) and the internal microphones:
   ```bash
   arecord -D hw:0,2 -f S16_LE -r 48000 -d 5 /tmp/headset.wav && aplay /tmp/headset.wav
   arecord -D hw:0,3 -f S16_LE -r 48000 -d 5 /tmp/mic.wav && aplay /tmp/mic.wav
   ```
   `hw:0,2` is the headset mic, `hw:0,3` the internal mics.
5. HDMI audio will stay silent. The topology has no DisplayPort playback.
6. Report what is audible, and send `debondragon-report`.

If `/proc/asound/cards` stays empty, the card never probed. Check
`dmesg` for the topology file and for SoundWire, and list
`/sys/bus/soundwire/devices`. Two likely causes: the ADSP firmware was
not copied, or the amplifiers are not the WSA8845 parts this devicetree
waits for (the whole card, headphones included, waits until they bind).
Boot the series-4 submenu entry; headphones should come back, and the
SoundWire list from that boot is the report we need.
