# Unreleased: kernel 7.2.0-debondragon-10, debondragon-support 0.4.2

Not a tagged release. The battery/DSP handoff, Wi-Fi, Bluetooth, touchpad and
boot were verified on the 83N3. The audio changes remain Experimental until
someone hears sound. It installs beside the older kernels, which remain the
rollback (docs/kernel-upgrade.md, "Try kernel series 10").

Kernel series 9 enables SquashFS LZO decompression and extended attributes.
Ubuntu's Chromium, Firefox and several desktop runtime snaps use
LZO-compressed SquashFS images; series 7 could not mount them. Series 8 could
mount them, but discarded the file capabilities that strict Snap confinement
requires. Series 8 remains available as the tested hardware rollback.

Kernel series 10 enables the Qualcomm Iris hardware video codec. Linux 7.2
already contains the X1P42100 Iris and video clock drivers, but its
`purwa.dtsi` still inherits X1E80100 clocks and leaves Iris disabled. The board
now carries the X1P clock and operating-point override merged upstream in
commit `43899c55d79b`, enables Iris, and selects the device-signed Lenovo
`qcvss8380.mbn`. The earlier `7.2.2-ideapad-iris1+` experiment used generic
firmware and the secure monitor rejected it with `-22`; support 0.4.2 now
exports and installs the Lenovo video firmware. Series 9 remains installed as
the no-Iris rollback until hardware decoding is verified.

## Battery status and the UEFI DSP handoff

Battery telemetry now works on hardware. The PMIC GLINK battery manager reports
AC online, the BYD L24B3PK2 battery present, charging status, voltage and energy
(62.24/62.86 Wh during the test, about 99%).

UEFI has already started the ADSP on this laptop, while its secure monitor
rejects a normal PAS reset. Kernel series 7 therefore preserves UEFI's SMP2P
state, detects and attaches to the running DSP, avoids the early platform/RPMsg
PMIC-GLINK probe race, and exposes the configured firmware path so `pd-mapper`
can find the adjacent service maps. The ADSP and CDSP devicetree nodes select
this attach-only mode with `qcom,broken-reset`.

The signed Lenovo firmware still cannot be redistributed. The Windows export
and Linux install helpers now include `adsps.jsn` with the other service maps.
After `debondragon-firmware` and a reboot, the kernel attaches to ADSP and the
battery power-supply devices appear.

Support 0.4.1 and later also select GRUB's firmware text console because
graphical GRUB input is severely delayed by this laptop's GOP. This affects
the boot menu only, not Linux graphics.

## Why the laptop was silent

The sound card, the WCD9385 and the DSP already came up on hardware, and
support 0.2.1 made PulseAudio show a Headphones sink. Nothing played:

- The default devicetree left the speaker amplifiers off and deleted the
  speaker playback link. The only playback device was Headphones, and that
  device is gated on the jack. With nothing plugged in there is no output.
- Turning the CRD's four-amp link back on would not have fixed it. That
  link also waits for a second amplifier pair on SoundWire 3. Those parts
  are not on this board (Windows' audio INF comments that group out), so
  the whole card, headphones included, would wait forever.
- Debian's two-speaker enable sequence sets `SpkrLeft`/`SpkrRight PA Volume`
  to 12. This kernel rejects anything above 6 (0 dB), and a rejected write
  aborts the sequence.
- Debian's WSA-macro init writes digital volume 84 on the unprefixed
  control. The control that exists is `WSA WSA_RX0/RX1 Digital Volume`,
  and the kernel limit is 81 (−3 dB).
- The headphone path included Debian's RX-macro enable sequence, which
  forces the ultra-low-power class-H mode. That mode does not drive the
  WCD9385 headphone outputs on these laptops. Class-AB (`CLS_AB_LOHIFI`)
  does.
- The internal microphones were powered from the WCD bias only. The
  VA-macro DMICs also need `VA MIC BIAS1`.
- The image did not install `alsa-ucm-conf`, `pulseaudio` or `alsa-utils`
  by name. The codec sequences the profile includes come from
  `alsa-ucm-conf`.

The device-signed ADSP firmware is still required. It cannot be shipped.
Without `qcadsp8380.mbn` (and the matching DTBs) under
`/lib/firmware/qcom/x1p42100/LENOVO/83N3/`, the card never probes.

## What changed

Kernel series 7, default board (the `-speakers` file is the same hardware,
so an old `DEBONDRAGON_DTB` still boots):

- Two WSA8845 on SoundWire 0, prefixes `SpkrLeft` and `SpkrRight`, CRD
  port maps kept. SoundWire 3 stays off. The playback link lists only
  those two amplifiers.
- Internal mics: `VA DMIC0/1` to WCD `MIC BIAS3` and `VA MIC BIAS1`.
- DisplayPort audio links stay deleted. HDMI audio is unsupported.

`debondragon-support` 0.4.2:

- UCM enables speakers at PA volume 6 and WSA digital volume 81, and
  headphones in class-AB. Speaker controls are written only when they
  exist, so this package still loads headphones on a series-4 kernel.
- Depends on `alsa-ucm-conf` (>= 1.2.12). Recommends PulseAudio (or
  PipeWire's Pulse compatibility) and `alsa-utils`. The ISO installs
  those packages.
- The redistributable T14s topology is still installed under the card
  name. That file has no DisplayPort graphs.
- The Windows and Linux firmware helpers include the device-signed Iris
  `qcvss8380.mbn`; the optional `qcvss8380_pa.mbn` is copied when present.

`DEBONDRAGON_HDMI=auto` already treats series 4 and later as HDMI-ok, so
series 10 keeps HDMI video on.

## How to test

`docs/hardware-testing.md`, section "Audio". Short version: install
support 0.4.2 and `linux-image-7.2.0-debondragon-10` beside series 9, run
`sudo debondragon-firmware` (or export the firmware from Windows), reboot
into series 10, and check `alsaucm -c hw:0 list _verbs` (HiFi),
`pactl list short sinks` (Speaker, and Headphones when the jack is
plugged), then play `hw:0,1` (speakers) and `hw:0,0` (headphones) at a
moderate volume. Headset mic is `hw:0,2`, internal mics are `hw:0,3`.

If `/proc/asound/cards` is empty, either the ADSP firmware is missing or
the amplifiers did not bind. Boot the series-4 submenu entry and report
`/sys/bus/soundwire/devices` plus `dmesg`.

## Still open

- No hardware confirmation that the amplifiers are WSA8845, or that any
  output is audible.
- No active speaker protection. The PA is capped at 0 dB; keep the volume
  moderate.
- HDMI audio stays silent.

---

# DebOnDragon v0.4.0

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
