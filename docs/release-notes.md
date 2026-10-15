# Unreleased: kernel 7.2.0-debondragon-12, debondragon-support 0.4.3

Not a tagged release. The battery/DSP handoff, Wi-Fi, Bluetooth, touchpad and
boot were verified on the 83N3. The audio configuration is inherited from the
hardware-verified series-5 work but has not been rechecked on series 12. It
installs beside the older kernels, which remain the rollback
(docs/kernel-upgrade.md, "Try kernel series 12").

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
firmware and the secure monitor rejected it with `-22`. Hardware testing found
that this 83N3 also rejects the display driver's non-PA image but accepts
`qcvss8380_pa.mbn`. Support 0.4.3 exports the PA image and installs it at the
series-10 path. FFmpeg selected the `iris_driver` decoder node (device numbering
varies between boots) and decoded all
90 frames of 1280x720 H.264 and HEVC samples, plus all 30 frames of a 640x360
VP9 sample. Low-resolution HEVC still triggers a firmware session error and is
tracked in `TO-FIX.md`.

Kernel series 11 also enables IPv4 and IPv6 policy routing plus the nftables,
connection-tracking, NAT and masquerading modules required by Tailscale and
Docker. Series 10 had a working TUN device, bridge and veth support, but
Tailscale still failed because policy routing returned `EOPNOTSUPP` and
Debian's iptables nft backend could not open its netfilter socket.
Series 11 restored peer connectivity and Docker container HTTPS egress on
hardware. Series 12 adds the connmark extension used by Tailscale's
reverse-path-filter workaround; without it the basic tunnel works but
`tailscale status` retains a router health warning.

Moonlight 6.1.0 exposed a separate userspace crash after successful Iris HEVC
decode: Ubuntu's libplacebo 7.349 called an unavailable Vulkan host-pointer
function while uploading the decoded frame. Backporting upstream libplacebo
commit `6eaaa9a68be5` fixes the crash while retaining both the Vulkan renderer
and Iris hardware decoding. This is tracked as a userspace packaging issue in
`TO-FIX.md`; `scripts/build-libplacebo-hotfix.sh` builds the removable local
package. It is not another firmware failure.

The same Qualcomm display driver 31.0.133.1 supplies an authenticated
`qcdxkmsucpurwa.mbn`. With that file, Mesa Turnip enumerates Adreno X1-45 and
Vulkan initializes successfully. The rejected firmware files are not part of
the repository or support package; device-signed files remain user-supplied.

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

The device-signed ADSP and Iris firmware is still not in the image. Copy it
with `debondragon-firmware` or `windows/Export-Firmware.ps1`.

## Mute and volume keys

F1, F2 and F3 (mute, volume down, volume up) are reported by the ITE keyboard
on a consumer-control evdev node, separate from the typing keys. Support 0.4.1
and later run `debondragon-volkeys`, which calls `pactl` for `KEY_MUTE`,
`KEY_VOLUMEDOWN` and `KEY_VOLUMEUP`.

## Series 10 support package

`debondragon-support` 0.4.3:

- UCM enables speakers at PA volume 6 and WSA digital volume 81, and
  headphones in class-AB. Speaker controls are written only when they
  exist, so this package still loads headphones on a series-4 kernel.
- Depends on `alsa-ucm-conf` (>= 1.2.12). Recommends PulseAudio (or
  PipeWire's Pulse compatibility) and `alsa-utils`. The ISO installs
  those packages.
- Restarts PulseAudio when the late ADSP sound card appears and handles the
  mute and volume keys.
- The redistributable T14s topology is still installed under the card
  name. That file has no DisplayPort graphs.
- The Windows and Linux firmware helpers require the device-signed Iris
  `qcvss8380_pa.mbn` and install it at the series-10 non-suffixed path.

`DEBONDRAGON_HDMI=auto` already treats series 4 and later as HDMI-ok, so
series 10 keeps HDMI video on.

## Why series 5 had to describe the speakers

Support 0.2.1 already made PulseAudio show a Headphones sink. Nothing played
until the default devicetree enabled the two WSA8845 amplifiers on SoundWire 0
and the UCM profile stopped using the Debian sequences that this kernel rejects
(PA volume 12, digital volume 84, class-H headphones). Details are in the board
notes. Series 4 remains a rollback: its devicetree does not wait for the speaker
amplifiers.

## Recheck audio on series 12

`docs/hardware-testing.md`, section "Audio". Short version: install
support 0.4.3 and `linux-image-7.2.0-debondragon-12` beside series 11, run
`sudo debondragon-firmware` (or export the firmware from Windows), reboot
into series 12, and check `alsaucm -c hw:0 list _verbs` (HiFi),
`pactl list short sinks` (Speaker, and Headphones when the jack is
plugged), then play `hw:0,1` (speakers) and `hw:0,0` (headphones) at a
moderate volume. Headset mic is `hw:0,2`, internal mics are `hw:0,3`.

If `/proc/asound/cards` is empty, either the ADSP firmware is missing or
the amplifiers did not bind. Boot the series-4 submenu entry and report
`/sys/bus/soundwire/devices` plus `dmesg`.

## Still open on series 12

- Reconfirm speaker, headphone and microphone behavior after the DSP-handoff
  and Iris changes; series 5 already verified speaker and headphone playback.
- No active speaker protection. The PA is capped at 0 dB; keep the volume
  moderate.
- HDMI audio stays silent.

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
