# Testing DebOnDragon on the 83N3

The README's support matrix only marks a component **Working** once it has
been seen working on the laptop. This page lists the tests for each
**Experimental** item and what to send back.

Run every test on the kernel that implements it (`uname -r`). The touchpad
test is series 3, HDMI is series 4, audio is series 5, the battery test uses
series 7, and hardware video uses series 10. Fan trips need kernel series 6.
Volume keys and the fan curve need support 0.5.1; the fan-curve readback and
the active-seat fix need support 0.5.2.
When done, collect everything with:

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

## Fan and thermals (kernel series 6, support 0.5.1)

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

**Fan reporter (opt-in, writes the EC).** Support 0.5.1 sends SoC Tj
(register 0x20, sensor 0x01, decidegrees Celsius: 65.1 °C is 651) and
installs a fan-1 curve (register 0x28) for profiles 1–7. The curve is
off below 52 °C, about 1600 rpm at 55 °C, about 2800 rpm at 70 °C, and
never above 4000 rpm. It does not change the selected profile, write
debug mode (`0x30`), or write EC enable (`0x35`). Around suspend it
writes modern-standby status (register 0x23).

On this laptop, support 0.5.0's temperature reports left the fan
physically stopped at 72.7 °C, and a light-load read at 55.9 °C was the
same: fan 1 at 0 rpm, fan 2 absent, profile 0x06. Support 0.5.1 then
wrote a curve; under load at 73.8 °C the fan was still stopped. Do not
disable the reporter. The reads below check whether that curve was
stored.

```bash
sudo apt install -o Dpkg::Options::=--force-confold ./debondragon-support_0.5.1_all.deb
systemctl is-active debondragon-fan.service
sudo journalctl -u debondragon-fan -b --no-pager | tail -n 20
sudo debondragon-fan status
```

`sudo` on the journal matters: this user is not in group `adm`, so a
plain `journalctl` is empty. The journal line to look for is
`programmed fan 1 curve for profiles 1-7`.

Then put a short load on and listen. Stop the load with Ctrl-C. Leave
the reporter running.

```bash
for i in $(seq 8); do timeout 90 sh -c 'while :; do :; done' & done
sleep 30
sudo debondragon-fan status
```

**Support 0.5.1 on this laptop.** The journal logged `programmed fan 1
curve for profiles 1-7, source 0x01, cap 4000 rpm`. After 30 seconds of
8-core load the hottest zone was 73.8 °C and fan 1 was still
`0x02 0x00 0x00` (0 rpm). Leave the reporter running. These reads do
not write a register. Paste the whole output. `sudo` matters.

```bash
sudo debondragon-fan probe
BUS=$(for a in /sys/bus/i2c/devices/i2c-*; do
	case $(readlink -f "$a/of_node" 2>/dev/null) in
	*i2c@b94000) echo "${a##*/i2c-}" ;;
	esac
done)
echo "bus $BUS"
echo "--- profile ---"
sudo i2ctransfer -f -y "$BUS" w1@0x76 0x24 r1
echo "--- fan 1 curve slots, profiles 1-7, temp source 0x01 ---"
for id in 0x11 0x21 0x31 0x41 0x51 0x61 0x71; do
	echo "lut $id"
	sudo i2ctransfer -f -y "$BUS" w5@0x76 0x28 "$id" 0x01 0x00 0x00 r65
done
echo "--- slot 0x61 with a zero second byte ---"
sudo i2ctransfer -f -y "$BUS" w5@0x76 0x28 0x61 0x00 0x00 0x00 r65
echo "--- firmware 0x0e ---"
sudo i2ctransfer -f -y "$BUS" w1@0x76 0x0e r4
```

Do not write `0x24`, `0x25`, `0x30`, or `0x35`. `0x35` = 0 is the DSDT
"SCI EC Disable" command.

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
Reboot so that notice does not linger. The curve write is runtime state;
a reboot without the reporter running returns the EC to the behavior it
had before 0.5.1. Do not write `0x30`, `0x24`, `0x25`, or `0x35`
yourself, and do not hand-send a different `0x20` value.

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

Needs kernel `7.2.0-debondragon-10` (or later), support 0.5.2, the authenticated
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

F1, F2 and F3 are mute, volume down and volume up. On the 83N3,
`libinput` reports `KEY_MUTE`, `KEY_VOLUMEDOWN` and `KEY_VOLUMEUP` on
the typing-keyboard node
(`/dev/input/by-path/platform-a84000.i2c-event-kbd`). That node is
`root:input` mode 660. Support 0.4.1 started `debondragon-volkeys` in
the user session, which cannot open it, and the failure was silent.
Do not add your user to group `input`: that group can read every
keyboard.

Support 0.5.1 runs the same program as a system service. It reads that
node as root, ignores every key except mute and volume, and calls
`pactl` as the active seat user. If the kernel exposes a separate
consumer-control node (volume keys, no letter keys) on the `a84000.i2c`
bus, a udev rule tags only that node `uaccess` for the active seat.
Support 0.5.1 opened the keyboard and then logged `no active seat` for
every key. Session 1 on this laptop is the logind manager and has no
seat; Hyprland is session 2 on `seat0`. Support 0.5.2 uses
`loginctl show-seat seat0 -p ActiveSession` and that session's user.
Installing it restarts the system service. Reboot only if it does not
come up active.

1. The system service is running. `sudo` on the journal matters: this
   user is not in group `adm`.
   ```bash
   systemctl is-active debondragon-volkeys.service
   sudo journalctl -u debondragon-volkeys -b --no-pager
   ```
   A line that says it is reading the typing keyboard as root is the
   expected path on this machine. `cannot open …: permission denied`
   means the device still cannot be read; the same line says not to
   join group `input`.
2. Press F1, F2 and F3 with a tune playing. F1 mutes, F2 lowers the
   volume, F3 raises it, in steps of 5%. The panel icon should follow.
3. If nothing changes, see which event the key actually produces:
   ```bash
   sudo libinput debug-events
   ```
   A working key prints `KEY_MUTE`, `KEY_VOLUMEDOWN` or `KEY_VOLUMEUP`.
   `KEY_F1` / `KEY_F2` / `KEY_F3` means the keyboard is in function-key
   mode (Fn+Esc toggles Fn Lock; the Esc LED shows it). Send the
   `libinput` lines, `journalctl -u debondragon-volkeys -b`, and
   `debondragon-report`.
