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
| TCPD `ELAN06FA` | IC20 → 0x88c000 → `i2c19` | 0x15 | touchpad (HID) | 0x3c0 → TLMM 3 |
| TSC1 `ELAN901C` | I2C9 → 0xa80000 → `i2c8` | 0x10 | touchscreen (HID) | 0x33 → TLMM 51 |
| UCS0 | I2C2/I2C4/I2C8 → `i2c1`/`i2c3`/`i2c7` | 0x08 | USB-C retimers (CRD layout) | |

The keyboard/touchpad interrupt values above 0xff are Windows' wake-capable
GPIO encoding. Every upstream X1 laptop uses TLMM 67 and TLMM 3 for these same
devices, and the touchscreen's 0x33 = 51 matches directly. The CRD puts
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
- Audio: ADSP subsystem ID `380317AA`. The speaker amplifiers aren't identified
  yet, so audio is disabled.

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
with matching lengths; 0x0E and 0x42 aren't in the ACPI map, so
`debondragon-ec-check` tests them read-only. The EC event pin is `_AEI` pin
0x140 (a wake-encoded number that can't be decoded directly). TLMM 66 is
inferred: the CRD's EC interrupt, wake-capable (PDC 142), and the only
nearby pin firmware leaves configured (`in high, no pull`).

**Audio.** Windows uses Qualcomm's CRD audio extension
(`qcaucd_ext_crd8380.inf`) with two SoundWire slaves (amplifier group on
instance 0, headset codec). The second amplifier group (instance 1) is
commented out, so this is a two-speaker layout like the ThinkBook 16, not
the CRD's four. The WCD9385 reset (TLMM 191) is held deasserted by
firmware, as on the CRD.

v0.2.0 audio: the default board enables the sound card for the WCD9385
headset codec (swr1/swr2) and the VA-macro DMICs, with speaker amps (swr0,
swr3) off and the USB-C DP audio links removed. The card is named
`X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10`. The kernel loads
`qcom/x1e80100/<card>-tplg.bin`, so debondragon-support installs the upstream
T14s AudioReach topology (same two-amp + WCD + VA graph) under that name,
plus a UCM profile derived from upstream `T14s-HiFi.conf` without the
speaker sequences. The opt-in `-speakers` board adds two WSA884x on swr0
(ThinkBook/T14s layout, controls `SpkrLeft`/`SpkrRight`) as card
`...-SPK`, which uses the upstream T14s UCM unchanged.
`scripts/check-ucm.sh` checks every UCM include against Debian's
alsa-ucm-conf.

## Open questions

- Confirm the backlight PWM channel on hardware (see above).
- Exact USB-C/USB-A port mapping and whether every CRD retimer is populated.
- Speaker amplifier type and count.
