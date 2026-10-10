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

## Open questions

- Confirm the backlight PWM channel on hardware (see above).
- Exact USB-C/USB-A port mapping and whether every CRD retimer is populated.
- Speaker amplifier type and count.
