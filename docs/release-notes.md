## debondragon-support 0.2.1 (installed systems; no new kernel)

Fixes from hardware testing of v0.2.0. Install with
`sudo apt install ./debondragon-support_0.2.1_all.deb` (it runs
`update-grub` itself), then reboot once. Both installed kernels
stay as they are.

- **HDMI off by default** (`video=HDMI-A-1:d` on the kernel command line).
  On v0.2.0, DisplayPort link training to the HDMI converter fails, the
  screen stays black, and unplugging the cable or disabling the output
  resets the laptop. Set `DEBONDRAGON_HDMI=on` in `/etc/default/debondragon`
  only to test a fix.
- **Brightness kept across boots**: saved once a minute when it changed
  (hard resets used to lose it, and systemd then restored its 5% floor,
  204/4095) and restored exactly at boot, so a deliberately low level stays
  low. Only without a saved level is it raised to at least
  `DEBONDRAGON_MIN_BRIGHTNESS` percent (default 30).
- **Default kernel can be pinned** (`DEBONDRAGON_DEFAULT_KERNEL`): GRUB then
  boots that kernel with its own devicetree by default, so a newer test
  kernel can be tried once with `grub-reboot` without becoming the default.
- **Audio profile loads**: ALSA cuts the card name to 31 characters, so
  v0.2.0's UCM file matched nothing. 0.2.1 adds it under the card's long
  name. Headphones, headset mic and internal mics; speakers stay off.

Still open: touchpad (interrupt pin, kernel series 3), HDMI link training,
EC/fan driver (protocol mismatch, stays off).

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
