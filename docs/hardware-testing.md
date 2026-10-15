# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the kernel that implements it (`uname -r`). The touchpad
test is series 3, HDMI is series 4, audio is series 5, the battery test uses
series 7, and hardware video decode uses series 10 with support 0.4.3. Volume
keys need support 0.4.1 or later. When done, collect everything with:

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

## GPU acceleration

Support 0.4.3 exports the Qualcomm display driver's platform-authenticated
`qcdxkmsucpurwa.mbn` and rebuilds the installed initramfs images. After a
reboot, verify that the secure monitor accepts it and Mesa selects Turnip:

```bash
sudo dmesg | grep -Ei 'adreno|gpu hw init|qcdxkms'
vulkaninfo --summary
```

**Verified on the 83N3 (2026-10-15):** display driver 31.0.133.1's INF lists
the machine's `ACPI\\VEN_QCOM&DEV_0D17&SUBSYS_CRD08380&REV_002F` ID. Its
`qcdxkmsucpurwa.mbn` (SHA-256
`2dc2883e76a8649f2b73c8c5f55f600ef6b1423acbbf30478c2d6e32a28af3a3`)
was accepted, and `vulkaninfo` enumerated `Adreno X1-45` with the Mesa Turnip
driver. An older cross-vendor copy was rejected with `-22` and must not be
reused.

## Hardware video decoding

Needs kernel `7.2.0-debondragon-10` (or later), support 0.4.3, the authenticated
`qcvss8380_pa.mbn` installed by `debondragon-firmware`, `v4l-utils`, and
`ffmpeg`. The helper copies that PA image to the non-suffixed path requested
by the series-10 devicetree. The non-PA image is rejected with error `-22`.
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

**Verified on the 83N3 (2026-10-15):** Qualcomm display driver 31.0.133.1's
`qcvss8380_pa.mbn` (SHA-256
`725711497ca962d76f62c4f3309dff51cf9f18b499bc252feb17588b9de3cfb1`)
registered Iris Decoder and Iris Encoder nodes. FFmpeg selected `/dev/video2`
with `iris_driver` and decoded all 90 frames of 1280x720 H.264 (15.5x
realtime) and HEVC (21.8x) samples, plus all 30 frames of a 640x360 VP9
sample. A 640x360 HEVC sample instead triggers firmware session error
`0x4000003`; that known gap is tracked in `TO-FIX.md`.

## Hardware video encoding

Use GStreamer for the direct encoder test. Video node numbering changes, but
the dynamically registered `v4l2h264enc` and `v4l2h265enc` elements select the
Iris Encoder node automatically:

```bash
gst-launch-1.0 -e videotestsrc num-buffers=90 pattern=smpte \
  ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 \
  ! v4l2h264enc output-io-mode=mmap capture-io-mode=mmap \
  ! filesink location=/tmp/iris-test.h264
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=codec_name,width,height,nb_read_frames \
  -of default=nw=1 /tmp/iris-test.h264
```

Repeat with `v4l2h265enc` and a `.hevc` output. On 2026-10-15 both pipelines
encoded all 90 1280x720 frames; ffprobe read 90 frames from each output and the
kernel logged no Iris error.

Do not use FFmpeg's `h264_v4l2m2m` as the encoder acceptance test yet. Ubuntu
FFmpeg 7.1.1 selects the Iris encoder but segfaults in libavcodec's V4L2 frame
copy before the first frame. The working GStreamer path isolates that as a
userspace integration bug; it is tracked in `TO-FIX.md`.

## Untested items

These are compiled but nobody has tested them yet. Any results help:

- USB-C data on both ports (plug in a USB-C stick, both orientations), and
  USB-A speed (`lsusb -t` shows 5000M for a USB 3 stick)
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
