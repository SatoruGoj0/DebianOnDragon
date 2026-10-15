# Unreleased (kernel series 6, support 0.5.0)

Not a tagged release. v0.4.0 stays on kernel series 5 and support 0.4.1.
Series 6 installs beside it.

## The fan was not seeing the SoC

On series 5, light use left every SoC thermal zone at 59–63 °C while the
battery read 30 °C and the PMICs 37 °C. The zones matching each other is
a fan that is off or barely spinning. Windows feeds die temperature to
the EC ("Temp to EC", register 0x20). Linux never did, and the CPU zones
had no passive trip short of a 115 °C shutdown.

Kernel `7.2.0-debondragon-6` adds a 75 °C passive trip on the CPU and
CPUSS zones (cluster 0 cools cpu0–3, cluster 1 cools cpu4–7) and lowers
the GPU passive trip from 95 °C to 85 °C. The 115 °C critical trips stay.
Nothing in the devicetree writes the EC.

`debondragon-support` 0.5.0 adds `debondragon-fan`. It is off until
`sudo debondragon-fan enable`. It reports SoC temperature (register 0x20,
decidegrees Celsius, sensors 0x01/0x02/0x03) and tells the EC about
suspend (register 0x23). It does not set RPM, replace the fan curve, or
write debug mode. `qcom-hamoa-ec` stays blacklisted: on this EC that
driver's reads are the wrong protocol and its probe would write debug
mode. Not confirmed on hardware. Steps and the power-off warning are in
docs/hardware-testing.md, "Fan and thermals".

## Mute and volume keys could not open the keyboard

Support 0.4.1 started `debondragon-volkeys` in the user session. On the
83N3 the keys arrive on `platform-a84000.i2c-event-kbd` (`KEY_MUTE`,
`KEY_VOLUMEDOWN`, `KEY_VOLUMEUP`). That node is mode 660, `root:input`.
The session user is not in group `input`, so the open failed, and the
program logged nothing.

Support 0.5.0 runs it as a system service. It opens the node as root,
ignores every key except mute and volume, and runs `pactl` as the
active seat user. If it cannot open a device it logs that, and the
message says not to add the user to group `input`. A udev rule grants
`uaccess` only to a consumer-control node on `a84000.i2c` that is not
the typing keyboard. The 0.4.1 user service is masked and its autostart
entry is removed. Not confirmed on hardware. Steps:
docs/hardware-testing.md, "Mute and volume keys".

---

# DebOnDragon v0.4.0

Kernel `7.2.0-debondragon-5` (Linux v7.2) and `debondragon-support` 0.4.1.
Series 5 is the default. It installs beside earlier kernels
(docs/kernel-upgrade.md, "Upgrade to v0.4.0").

## Audio works

Verified on the 83N3 with series 5 and support 0.4.0: the sound card and
the HiFi profile come up, PulseAudio lists Speaker and Headphones, and
`speaker-test` plays Front Left. Front Right is silent on this unit in
Debian and in Windows, so that speaker is a hardware fault. Headset and
internal microphones are not confirmed yet. HDMI audio stays silent (the
topology has no DisplayPort graphs). HDMI video stays on.

The PA volume is capped at 0 dB. There is no active speaker protection.
Keep the volume moderate.

## After boot, PulseAudio stayed on auto_null

PulseAudio starts at login. The sound card appears only once the ADSP
firmware has loaded, which is later, and PulseAudio then kept `auto_null`
until `systemctl --user restart pulseaudio`. Support 0.4.1 restarts it
once a playback PCM shows up, and only if the sinks are still `auto_null`.

## debondragon-firmware

`debondragon-firmware` with no arguments failed with "No Windows
DriverStore or firmware folder found" when the Windows NTFS partition was
already mounted at `/mnt/windows` (mounting it again fails, and the
existing mount was ignored). It now uses an NTFS filesystem that is
already mounted. `--help` prints the usage; it used to be treated as a
folder path. Passing the FileRepository path still works.

The device-signed ADSP firmware is still not in the image. Copy it with
`debondragon-firmware` or `windows/Export-Firmware.ps1`.

## Mute and volume keys

F1, F2 and F3 (mute, volume down, volume up) did nothing. Support 0.4.1
runs `debondragon-volkeys` in the user session and calls `pactl` for
`KEY_MUTE`, `KEY_VOLUMEDOWN` and `KEY_VOLUMEUP`. Hardware later showed
those events on the typing-keyboard node
(`platform-a84000.i2c-event-kbd`), which that user service cannot open,
and the failure was silent. The fix is in support 0.5.0 (above). v0.4.0
itself is unchanged.

## Why series 5 had to describe the speakers

Support 0.2.1 already made PulseAudio show a Headphones sink. Nothing
played until the default devicetree enabled the two WSA8845 on SoundWire
0 and the UCM profile stopped using the Debian sequences that this kernel
rejects (PA volume 12, digital volume 84, class-H headphones). Details
are in the board notes. Series 4 remains a rollback: its devicetree does
not wait for the speaker amplifiers.

---

## HDMI video (kernel series 4, support 0.3.0)

Kernel `7.2.0-debondragon-4` (Linux v7.2) and `debondragon-support` 0.3.0.
Installs beside earlier kernels; don't reinstall Debian
(docs/kernel-upgrade.md, "Upgrade from v0.3.0").

## HDMI works

Verified on the 83N3 with a Samsung LS27D300G: 1920x1080@60 over a
4-lane HBR2 DisplayPort link to the HDMI converter (Parade PS176), extended
desktop under Hyprland with pointer and windows moving between screens.

The fix is one devicetree line: the DP lane orientation of the PHY that
feeds the converter (`data-lanes = <3 2 1 0>`; the earlier `<0 1 2 3>`
made link training fail). Kernel -4 is otherwise identical to -3.

`debondragon-support` 0.3.0 turns HDMI on automatically
(`DEBONDRAGON_HDMI=auto`) for kernels with this fix and keeps it off for
older ones; GRUB's "DebOnDragon kernels" submenu has a "HDMI off" entry
for -4 as a fallback. No sysfs commands needed.

**Not yet verified:** HDMI at boot and hotplug with the new automatic
setting, long runs, reboot and unplug/replug with active video (earlier
kernels reset the laptop on unplug after failed training). Tests:
docs/hdmi-testing.md.

## Bluetooth headsets: microphone and Earbuds app

- `debondragon-support` 0.3.0 makes PulseAudio register the Bluetooth
  headset profiles itself (`/etc/pulse/default.pa.d/debondragon-bluetooth.pa`,
  native backend). Before, headsets could only play music; their
  microphone was unusable. It also reports headset battery levels to BlueZ.
- `apps/earbuds/`: a GTK 4 + libadwaita app (pair, connect, music vs.
  call mode, volume, microphone level, battery) and a Waybar module; install
  with `apps/earbuds/install.sh`. Noise-control switching for realme earbuds
  isn't possible yet (undocumented protocol). Not yet tested with real
  earbuds.

Unchanged and still working: touchpad (TLMM 19), internal display, GPU,
brightness, camera, Wi-Fi, keyboard, touchscreen, USB-A.

---

# DebOnDragon v0.3.0

For the Lenovo IdeaPad Slim 3 15Q8X10 (83N3, Snapdragon X X1-26-100).
Kernel series `7.2.0-debondragon-3` (Linux v7.2) and `debondragon-support` 0.2.1.

**Installed system: don't reinstall.** The new kernel installs **beside**
7.2.0-debondragon-2. Test it once without changing the default:
https://github.com/SatoruGoj0/DebianOnDragon/blob/main/docs/kernel-upgrade.md
("Test a new kernel once, keeping the current one as default").

## Verified on hardware

- **Touchpad works** (kernel `7.2.0-debondragon-3`): its interrupt is on
  TLMM 19, decoded from the DSDT, not the CRD's TLMM 3. Interrupts arrive,
  libinput reports continuous pointer motion, normal use is fine.
- Kernel -3 boots; HDMI stays off (`video=HDMI-A-1:d`).
- Audio: the UCM profile now loads and PulseAudio offers a Headphones sink
  (was `auto_null`). Sound output itself is **not tested yet**.
- Confirmed on v0.2.0 and unchanged here: internal display and GPU
  acceleration, brightness control, camera, Wi-Fi, keyboard, touchscreen,
  USB-A, temperature sensors (on -3: display up, camera enumerates).

Still broken: HDMI (link training fails; unplugging used to reset the
laptop, hence off by default). The EC/fan driver's protocol doesn't match
this EC (driver stays off; the EC runs the fan itself).

## Changes

`debondragon-support` 0.2.1 (works with kernel -2 as well):
- **HDMI off by default** (`video=HDMI-A-1:d`), so the failing link is
  never enabled and there is nothing to tear down. Reversible:
  `DEBONDRAGON_HDMI=on` in `/etc/default/debondragon`, only to test a fix.
- **Brightness**: saved once a minute when it changed and restored exactly
  at boot; without a saved level, at least `DEBONDRAGON_MIN_BRIGHTNESS`
  (30%). Restore across a reboot not yet confirmed.
- **Audio profile** under the card's long name, which is what ALSA looks up
  (the short name is cut to 31 characters). Speakers stay off.
- **`DEBONDRAGON_DEFAULT_KERNEL`** pins GRUB's default to one kernel with
  its own devicetree, so a new kernel can be tried once with `grub-reboot`.

Kernel `7.2.0-debondragon-3`:
- **Touchpad interrupt on TLMM 19** (was the CRD's TLMM 3, which never
  fired), level-low with pull-up, decoded from the DSDT
  (`docs/board-notes.md`). **Verified on hardware.**
- **Absent PMIC (SPMI SID 0xa) disabled**: stops a failing probe and its
  boot WARNING. No working device used it.
- **`/dev/drm_dp_auxN`** (read-only HDMI diagnostics) and **lockup / hung
  task detectors** (report only, never reboot). HDMI link training is
  **not** fixed yet.
- USB tethering drivers (RNDIS, ipheth).

EC/fan driver: still blacklisted.

---

Previous release (v0.2.0):

DebOnDragon for the Lenovo IdeaPad Slim 3 15Q8X10 (83N3, Snapdragon X X1-26-100).
Linux v7.2 kernel series `7.2.0-debondragon-2`.

**Installed system:** don't reinstall. Download `linux-image-7.2.0-debondragon-2_*.deb`,
`debondragon-support_*_all.deb` and `SHA256SUMS`, then follow
https://github.com/SatoruGoj0/DebianOnDragon/blob/main/docs/kernel-upgrade.md
The new kernel installs **next to** the old one. GRUB's "DebOnDragon kernels"
submenu boots either one with its own devicetree.

New in this kernel (implemented from hardware evidence; **not yet tested on hardware**):
- Touchpad: interrupt pull-up fix for the `incomplete report` floods
- Display brightness: PWM moved to pmk8550 GPIO 5
- HDMI: DP2 → DP-to-HDMI bridge
- Internal camera: usb_2 + eUSB2 repeater
- Audio: headphones, headset mic and internal mics (DSP topology and UCM come
  with debondragon-support; needs `debondragon-firmware`)
- Internal speakers: **opt-in** `-speakers` devicetree (no speaker protection on Linux)
- Fan/EC driver: built but **off by default**; check with `sudo debondragon-ec-check`

Test steps and the support matrix:
https://github.com/SatoruGoj0/DebianOnDragon/blob/main/docs/hardware-testing.md

**New install:** write the ISO in DD mode, boot it from the USB-A port,
and keep Secure Boot off (https://github.com/SatoruGoj0/DebianOnDragon/blob/main/docs/install.md).
