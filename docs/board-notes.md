# 83N3 board notes: where the devicetree comes from

All data was collected read-only on the laptop itself. Raw sources are in
`hardware-reports/`; the DSDT can be decompiled with `scripts/acpi-extract.sh`.

## Identity

- SMBIOS: LENOVO 83N3, family "IdeaPad Slim 3 15Q8X10", BIOS RVCN18WW (Insyde)
- CPU: Snapdragon X X1-26-100, 8 cores. This is the Purwa die (`purwa.dtsi`,
  same family as X1P-42-100).
- Most Qualcomm ACPI devices carry `SUBSYS_CRD08380`: the board is derived from
  Qualcomm's X1 CRD reference design. That's why the devicetree starts from `x1-crd.dtsi`.

## I2C devices (from `\_SB` in the DSDT)

ACPI names QUP instances 1-based, Linux 0-based. The MMIO base pins it down.

| ACPI device | Bus (ACPI → base → Linux) | Addr | Device | IRQ GPIO |
|---|---|---|---|---|
| ECKB `QTEC0001` | IC10 → 0xa84000 → `i2c9` | 0x3a | keyboard (HID) | 0x180 → TLMM 67 |
| TCPD `ELAN06FA` | IC20 → 0x88c000 → `i2c19` | 0x15 | touchpad (HID) | 0x3c0 → **TLMM 19** (not 3, see below) |
| TSC1 `ELAN901C` | I2C9 → 0xa80000 → `i2c8` | 0x10 | touchscreen (HID) | 0x33 → TLMM 51 |
| UCS0 | I2C2/I2C4/I2C8 → `i2c1`/`i2c3`/`i2c7` | 0x08 | USB-C retimers (CRD layout) | |

GpioInt pin values of 0x100 and up are not TLMM numbers. They are
`0x40 × n`, where n indexes the `Interrupt` list in `\_SB.GIO0._CRS`; that
interrupt's GIC SPI maps to a TLMM pin through `GIO0.CIPR` (returned by the
PDC `_DSM`, entries `{PDC index, TLMM pin, SPI}`, identical to the kernel's
`x1e80100_pdc_map`). Decoded:

| Pin value | `_CRS` # | SPI | TLMM | User |
|---|---|---|---|---|
| 0x100 | 4 | 0x256 | 71 | |
| 0x140 | 5 | 0x2f8 | 66 | EC (`_AEI`) |
| 0x180 | 6 | 0x253 | 67 | keyboard ✓ (interrupts seen on hardware) |
| 0x1c0 | 7 | 0x293 | 193 | |
| 0x200–0x300 | 8–12 | | 145, 148, 151, 154, 157 | |
| 0x340 | 13 | 0x2f4 | 92 | lid (`_AEI`) |
| 0x380 | 14 | 0x252 | 59 | |
| 0x3c0 | 15 | 0x240 | **19** | touchpad |

Keyboard (67), lid (92) and EC (66) agree with what the upstream X1 laptops
use, which confirms the decoding; the touchpad does **not** use TLMM 3 here.
The touchscreen's 0x33 = 51 is a plain TLMM number. The CRD puts
keyboard and touchpad on `i2c0`; the 83N3 does not use `i2c0` at all.

The DSDT picks one of four touchpads (ELAN 0x15, Synaptics 0x2c, FocalTech
0x38, Goodix 0x5d) at runtime, so all four are described.

## PCIe (Windows `DEVPKEY_Device_BiosDeviceName`)

| ACPI | Linux | Device |
|---|---|---|
| `\_SB.PCI4.RP1.WLN` | `pcie4` | Qualcomm FastConnect 7800 / WCN7850 (17cb:1107) |
| `\_SB.PCI5.RP1.MHI1` | `pcie5` | BayHub SD reader (1217:8621), on the CRD's WWAN slot |
| `\_SB.PCI6.RP1.NVME` | `pcie6a` | NVMe SSD (1344:5425) |

## Other

- Panel EDID vendor/product: LEN 0x9197, an LCD. The CRD's Samsung OLED
  compatible is replaced with generic `edp-panel`.
- Bluetooth: `QCOM0C6B` on UR15 (0xa98000) → `uart14`.
- Audio: ADSP subsystem ID `380317AA`. Two WSA8845 on SoundWire 0, WCD9385
  headset codec, two VA-macro DMICs. Details in the Audio section below.
  The ADSP firmware is device-signed and is not in the image.

## Display and backlight

The DSDT embeds Qualcomm panel-config XML for the panels Lenovo ships
(`scripts/acpi-panels.sh` lists them). The entry for this unit's panel
(EDID `30 AE 97 91`, "LEN153WUXGA") carries a Lenovo change marked "Modify
for LCD Backlight PWM": `BacklightType` 1 (PMIC PWM), control type 4, bank 0,
14-bit, 2000 Hz.

The first hardware boot (v0.1.0, which had no backlight node) went black
when `msm` loaded from the initramfs at about 7 s. v0.1.1 describes the
backlight like the Lenovo ThinkBook 16 Gen 7: pm8550 LPG channel 3 at 2 kHz,
VBL9 switched by PMC8380 GPIO 10, enable on PMC8380 GPIO 4. The ASUS
Zenbook A14 LCD instead uses pmk8550 PWM channel 0 on PMK8550 GPIO 5; if
the ThinkBook wiring is wrong, `debondragon-report` (PMIC pin functions)
shows which one the firmware set up.

### Hardware boot logs (v0.1.2, DODLOG partition)

- The panel reports EDID **CMN 0x1567** (Innolux) over AUX, not the LEN
  0x9197 Windows shows; panel-edp doesn't know it and uses conservative
  timings (a WARN, not fatal).
- msm never bound: the USB-C DP controllers (dp0-2) wait on aux bridges
  that need pmic_glink, i.e. the ADSP firmware, which the live system
  lacks. Without msm, panel-edp powers the panel down after probe.
- In safe graphics, regulator cleanup at ~38 s switched off VREG_EDP_3P3
  and VBL9, blanking the firmware framebuffer.
- Working: systemd boot, Bluetooth (WCN7850 over UART, firmware loads),
  keyboard (Ctrl+Alt+Delete reboots cleanly).

v0.1.3: dp0-2 disabled, `regulator_ignore_unused` on all entries, and safe
graphics also blocks panel_edp, pwm_bl and leds_qcom_lpg.

## v0.2.0 findings

Sources: DSDT (decompiled), `REPORT.TXT` from the v0.1.4 live session
(live TLMM/PMIC pin states, PWM state, `dmesg`), Windows driver INFs.
`scripts/acpi-pep-gpios.sh` lists the GPIO actions in the PEP power tables.

**Touchpad.** `dmesg` showed `i2c_hid_of 0-0015: incomplete report (31/255)`
floods. TLMM 3 read `in low, no pull`: the active-low IRQ line was asserted
permanently. The DSDT declares the IRQ `GpioInt(Level, ActiveLow, ..., PullUp)`
and the ThinkBook 16 (same ELAN06FA) uses `bias-pull-up`; the CRD state I
inherited has `bias-disable`. Fix: pull-up on `tpad_default`.

v0.2.0 on hardware: no `incomplete report` any more, but no input either.
TLMM 3 (now pulled up) counted **0** interrupts while the keyboard and
touchscreen counted theirs, i2c-hid logged `device did not ack reset within
1000 ms` (the reset ack is an interrupt), and sampling every TLMM input
while touching showed no pin changing. The ≤ v0.1.4 floods were TLMM 3
floating, not the touchpad. Decoding 0x3c0 (above) gives TLMM 19, which
firmware leaves `in, no pull`. TLMM 19 did not change during the sampling
either; it differed only between two snapshots taken in different boots
(low, then high). That fits a line nobody pulls up, and a touchpad that
never finished its reset handshake, but it is not proof. Fix to test
(kernel series 3): interrupt on TLMM 19 with `bias-pull-up`, as the DSDT's
`PullUp` says.

**Backlight.** The PEP table of the display device `\_SB.GPU0` configures
PMC8380 GPIO 4 (backlight enable) and PMK8550 GPIO 5. Firmware leaves PMK8550
GPIO 5 in `func3` (PWM out). The panel config XML says PMIC PWM, bank 0,
2 kHz. That is the ASUS Zenbook A14 LCD wiring: `pmk8550_pwm` channel 0. The
pm8550 LPG channel 0 that firmware also leaves running (pm8550 GPIO 7,
`func1`) is not owned by the display, so it's left alone.

**HDMI.** `GIO0._AEI` lists TLMM 126 (edge) and `_EVT` maps it to
`Notify(\_SB.GPU0, 0xD1)`: display hot-plug. `GPU0` also sets TLMM 126 to
function 1 (`usb2_dp`). `GPU0.ROE5/ROE6` (DP2 only) carry a Lenovo
`DPFixedLanedConfiguration=1`. `URS2` (usb_1_ss2) has `_STA` 0. So DP2 runs
over usb_1_ss2's QMP PHY as a fixed DP link to an always-on DP-to-HDMI bridge.
The CRD's third USB-C port (retimer on i2c1, pmic-glink connector@2, and the
`vreg_rtmr2_*` supplies, one of which claimed TLMM 126 and drove it low) is
removed. Lane order `<0 1 2 3>` is the default with no swap described;
unverified.

### HDMI link training (kernel series 4)

**Path (confirmed, DTB + sysfs on hardware):** MDSS `dp2`
(`displayport-controller@ae9a000`) → `phys = <&usb_1_ss2_qmpphy
QMP_USB43DP_DP_PHY>` (`phy@fdf000`) → PHY `port@0/endpoint@0` →
`/hdmi-bridge` (simple-bridge) → `/hdmi-connector`. `/dev/drm_dp_aux1` is
dp2's AUX channel (`/sys/class/drm_dp_aux_dev/drm_dp_aux1` → `ae9a000`);
`aux0` is the eDP panel (`aea0000`). The PHY's DRM aux bridge
(`aux_bridge.aux_bridge.2`, parent `fdf000.phy`) binds. The deferred
`aux_bridge.0`/`.1` belong to `fd5000.phy`/`fda000.phy` (USB-C ports 1 and
2) and wait on the CRD retimers that don't answer: not part of HDMI.

**Failure on series 2 (hardware log, msm `dp_ctrl.c`):** first attempt:
clock recovery passed, channel EQ failed (`link training #2 ... -110`).
Since CR still held, the driver dropped lanes; every retry then failed CR
at maximum swing (`max v_level reached` → -EAGAIN), and the fallback ended
in `-ECONNRESET` (`Failed link training (rc=-104)`). The DPU encoder was
enabled anyway; with no DP link there is no pixel clock, hence the endless
`vblank timeout` / `frame done timeout`. EDID and hot-plug only use AUX and
HPD, which is why the connector looked fine while the screen stayed black.

**Cause (hypothesis, strongly supported):** mirrored lane order.
`phy-qcom-qmp-combo` without `mode-switch` takes its mode and orientation
from `data-lanes` on `port@0/endpoint@0`: `<3 2 1 0>` = DP-only NORMAL,
`<0 1 2 3>` = DP-only REVERSE (`dp_data_lanes[]`). Orientation sets the
lane mux (`SW_PORTSELECT_VAL`) and, below 4 lanes, which lane pair is
powered (`qmp_combo_configure_dp_mode`). Series 2/3 used the ThinkBook 16's
`<0 1 2 3>`. A mirrored order explains both phases: with 4 lanes every lane
carries TPS1, so CR locks, but the receiver de-skews lanes in order and EQ
fails; with 2 lanes the wrong pair is powered, so the converter's lanes 0/1
see nothing and CR fails at any swing. Four of the five upstream X1 boards
with HDMI on `usb_1_ss2` (Zenbook A14, Vivobook S15, ThinkPad T14s, Medion)
use `<3 2 1 0>`; their nodes are otherwise identical to ours. Series 4
changes only this.

**Converter: Parade PS176 (DPCD on hardware, kernel -4, HDMI forced
off).** `/dev/drm_dp_aux1` 0x000: `12 14 c4 01 01 15 01 81 00 01 04 01 0f 00
01 00` = DPCD 1.2, max link rate 0x14 (HBR2, 5.4 Gbps/lane), 4 lanes with
enhanced framing and TPS3 (0xc4), one downstream port of type DVI/HDMI with
detailed caps (0x15), AUX read interval 4 ms. 0x500: `00 1c f8 31 37 36 47
42 30 00 c7 55 00` = branch IEEE OUI 00-1C-F8 (Parade Technologies),
device ID "176GB0" (PS176, DP 1.2 to HDMI 2.0), HW rev 0xc7, FW 0x55.00.
The DSDT names no converter and the Windows DriverStore has no driver for
one. `realtek,rtd2171` stays as the compatible for now: simple-bridge has no
PS176 entry and treats all HDMI converters alike (connector type only), so
it doesn't affect training. DPCD can't show board wiring (lane order,
polarity); only training results can.

**Verified on hardware (kernel -4, 2026-10-14).** With `<3 2 1 0>`:
`msm_dp_ctrl_on_link: rate=540000, num_lanes=4, pixel_rate=148500`, link
training #1 and #2 successful on the first attempt (then again for the
stream), no retries, no `v_level`/timeout messages; Samsung LS27D300G shows
1920x1080@60, extended desktop under Hyprland. The orientation was the
cause. `check-dtb.sh` asserts `<3 2 1 0>` in every build.

**Reset on unplug/disable (unexplained):** happened only after failed
training, with the encoder running without a link. No panic, no pstore, no
journal entry. Series 3+ have lockup/hung-task detectors (report only).
HDMI stays off by default until a test shows training works.

**Camera.** `\_SB.USB4` (MMIO 0xa200000 = `usb_2`) contains
`RHUB.PRT0.CAM0` (Windows: USB 13d3:54bf), drives TLMM 7 (GpioIo, pulled up)
and its PEP entry votes LDO4_B and LDO13_B (eUSB2 repeater supplies) plus
LDO2_E/LDO3_E (USB2 PHY). That is the ThinkBook 16's `usb_2` design: PTN3222
repeater at i2c5 0x4b, reset on TLMM 7. No camera power GPIO appears in the
DSDT.

**Fan / EC.** `FAN1`/`FAN2` (PNP0C0B) and `FECI` (QCOM0D05) talk to the EC
through `\_SB.I2C6._DSM`. `I2C6` (= Linux `i2c5`) defines a GenericSerialBus
region at address 0x76 with command registers 0x05, 0x20–0x2F, 0x30 (7-byte
raw), 0x32, 0x34, 0x35, 0x62–0x66, 0x81–0x89, 0x8E, 0x8F. The upstream
`qcom-hamoa-ec` driver (binding: address 0x76) writes 0x23, 0x30 (+6 bytes)
and 0x35, and reads 0x05, 0x0E and 0x42. All of its writes exist on this EC
with matching lengths, but they do not mean what that driver thinks: 0x30
is "Fan Debug Mode" (direct PWM), 0x23 is modern-standby status, and
0x0E/0x42 are not in the ACPI map. Hardware reads fan count 0 from 0x42.
The driver stays blacklisted. Enabling it would write debug mode.

Windows does not set RPM. `\_SB.I2C6._DSM` function 1 ("Temp to EC") writes
register 0x20: sensor id, a 0x02 length, and a 16-bit temperature. TZ31
(all eight Oryon cores) forces sensor 0x02; TZ32 (GPU) forces 0x03. The
same FC20 block is what keeps the fan curve alive on other X1 laptops.
`debondragon-fan` (support 0.5.1, opt-in) sends that report in decidegrees
Celsius on sensor 0x01 only, which is the SoC Tj source in Qualcomm's
Hamoa EC driver (651 means 65.1 °C). It also writes the fan-1 LUT
(register 0x28, 68 bytes, temp source 0x01) for profiles 1–7, because
that driver programs the LUT itself and temperature reports alone left
the fan stopped. The table follows the Hamoa breakpoints and never asks
for more than 4000 rpm. It writes 0x23 only to tell the EC about suspend.
It does not write 0x24, 0x25, 0x30 or 0x35, and it does not program fan 2.
TZ31's ACPI passive trip is 0x0D48 (67 °C); TZ31 critical is 0x0E92
(100 °C). The SoC dtsi only had a 115 °C critical trip on the CPU zones,
so series 6 adds a 75 °C passive trip on each CPU and CPUSS zone and
lowers the existing GPU passive trip from 95 °C to 85 °C. Critical trips
stay at 115 °C.

On series 5, light use held every SoC zone at 59–63 °C while the battery
read 30 °C and the PMICs 37 °C. On series 6 with support 0.5.0 reporting,
72.7 °C under load still left the fan physically stopped, and a later
light-load read at 55.9 °C was the same: fan 1 at 0 rpm, fan 2 absent
(speed byte count 0), thermistors `0x29`–`0x2d` all 0, profile 0x06.
Profile 0x06 is best-performance on AC. The curve ids that were read
(`0x00`, `0x10`, `0x01`) are not the fan-1 profile-6 slot; that id is
0x61. The DSDT SoC fan zone (`TZ98`) engages active cooling at 0x0D3E,
about 66 °C. `debondragon-fan probe` reads the 0x61 slot and does not
write it.

The EC event pin is `_AEI` pin 0x140 (a wake-encoded number that can't be
decoded directly). TLMM 66 is inferred: the CRD's EC interrupt,
wake-capable (PDC 142), and the only nearby pin firmware leaves configured
(`in high, no pull`).

**Audio.** Windows uses Qualcomm's CRD audio extension
(`qcaucd_ext_crd8380.inf`) with two SoundWire slaves (amplifier group on
instance 0, headset codec). The second amplifier group (instance 1) is
commented out, so this is a two-speaker layout like the ThinkBook 16, not
the CRD's four. The WCD9385 reset (TLMM 191) is held deasserted by
firmware, as on the CRD.

Kernel series 7 enables that two-speaker card on the default board.
The CRD's four-amp playback link waits for a second pair on swr3; those
parts are absent, so that link is replaced with the two WSA8845 already
described on swr0 (`speaker@0,0` / `speaker@0,1`, port maps left as the
CRD wrote them) plus the WSA macro. Their prefixes are `SpkrLeft` and
`SpkrRight`. swr3 stays disabled. The USB-C DP audio links stay removed:
the T14s topology this card loads has no DisplayPort graphs, so HDMI audio
is unsupported. The card name stays
`X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10` so the topology filename does not
change. ALSA's 31-character card id truncates it; the UCM profile is also
installed under that truncated id and under the DMI long name.

Internal mics are the two VA-macro DMICs. They need both WCD `MIC BIAS3`
and `VA MIC BIAS1`. The CRD's extra DMIC2/DMIC3 route to `MIC BIAS1` is
not this laptop.

`debondragon-support` 0.4.2 installs the T14s AudioReach topology under
the card name and a UCM profile that drives speakers, headphones, the
headset mic and the internal mics. It does not include Debian's speaker
sequence (that writes PA volume 12, which this kernel rejects; the limit
is 6, which is 0 dB) or Debian's WSA-macro init (digital volume 84 on an
unprefixed control; the prefixed limit is 81, which is −3 dB). Headphone
playback is class-AB (`CLS_AB_LOHIFI`); Debian's RX-macro enable sequence
selects the ultra-low-power class-H mode, which does not drive these
WCD9385 outputs. Speaker and WSA controls are written only when they
exist, so the same package still loads headphones on a series-4 kernel
that has no amps. `scripts/check-ucm.sh` checks every UCM include against
Debian's alsa-ucm-conf. The `-speakers` devicetree is the same file as
the default board, so an old `DEBONDRAGON_DTB` setting still boots.

On the 83N3 with series 5 and support 0.4.0, the card and the HiFi profile
come up and Front Left plays. Front Right is silent in Debian and in
Windows on this unit, which is a failed speaker, not a missing channel.
The keyboard (QTEC0001, HID vendor 048D, i2c controller `a84000`) is one
I2C HID device. Windows collection 2 is consumer control (mute, volume
down, volume up). On the 83N3 those events arrive on the typing-keyboard
evdev node (`platform-a84000.i2c-event-kbd`), which is mode 660,
`root:input`. Support 0.4.1's user service could not open it and logged
nothing. Support 0.5.1 runs `debondragon-volkeys` as root, discards every
key except mute and volume, and does not put the user in group `input`.
A udev `uaccess` tag applies only to a consumer-control node on that bus
that is not the typing keyboard, if the kernel splits one out.

**Battery and DSP handoff (kernel series 7).** UEFI leaves the ADSP running,
but Linux v7.2 originally overwrote its SMP2P state and then tried a PAS reset
that this machine's secure monitor rejects. A downstream SMP2P/remoteproc
handoff series, plus an attach-only `qcom,broken-reset` mode on ADSP and CDSP,
lets Linux attach to the booted DSP. A PMIC-GLINK probe-order fix handles the
RPMsg endpoint that appears during early boot, and remoteproc sysfs retains the
configured firmware path so `pd-mapper` finds the adjacent JSON service maps.
With the matching 83N3 ADSP firmware installed, hardware reports AC online and
the BYD L24B3PK2 battery's status, voltage and energy through `qcom-battmgr`.

**smb2360 PMICs (v0.2.0 boot log).** The CRD has three smb2360 at SPMI
SIDs 0x7, 0xa and 0xb, each with the eUSB2 repeater of one USB-C port. On
the 83N3, SIDs 0x7 and 0xb answer and their repeaters bind; SID 0xa fails
(`0xa 0x104: transaction failed`, `pmic-spmi 1-0a` error -5, with a
WARNING). The CRD gives SID 0xa's repeater to `usb_1_ss1_hsphy` (second
USB-C port, USB 2.0), so `fd9000.phy` and `a800000.usb` have never probed
here. Kernel series 3 disables the SID 0xa node; that only stops the failing
probe (the phy core returns -EPROBE_DEFER for an unregistered provider, so
the port keeps deferring as before). Windows' PEP table for `\_SB.USB1`
votes LDO14_B and LDO3_D, the CRD's supplies for the SID 0xa repeater, so it
doesn't say which PMIC the repeater is on. Two answering smb2360 for two
USB-C ports suggests SID 0xb; unverified.

The CRD's USB-C retimers for ports 0 and 1 (`ps883x` at 0x08) don't answer
either (-6; the ss2 one is already removed), which keeps
`pmic_glink_altmode` waiting ("failed to acquire retimer-switch for port:
0"); USB-C alt mode stays unsupported.

## Open questions

- Confirm the backlight PWM channel on hardware (see above).
- Second USB-C port: is its eUSB2 repeater the smb2360 at SID 0xb?
- Exact USB-C/USB-A port mapping and whether every CRD retimer is populated
  (none of the three answered on hardware).
- Headset and internal microphones, and the mute/volume keys
  (docs/hardware-testing.md).
