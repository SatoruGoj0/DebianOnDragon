# Upstreaming the Lenovo IdeaPad Slim 3 15Q8X10 (83N3)

Goal: mainline Linux supports this exact laptop, so distributions need no
DebOnDragon kernel. DebOnDragon stays the test environment until then.
Nothing here has been sent to anyone; sending is a human decision.

State checked 2026-10-14 against mainline **v7.3-rc7** (`24a19b953e2a`)
and **linux-next 20261013** (`1fffefb00`). The mailing-list archive (lore)
refuses automated access, so pending, unmerged submissions still have to
be searched there by hand before anything is sent.

## 1. Baseline and what DebOnDragon changes

DebOnDragon builds **unmodified Linux v7.2** (`KERNEL_REF=v7.2`). There
are **no kernel source patches**. Everything kernel-side is:

| DebOnDragon change | Where | Upstream class |
|---|---|---|
| Board devicetree (`dts/*.dtsi`, `*.dts`) | added to `arch/arm64/boot/dts/qcom` at build time | Board-specific DT addition (needs rework, §3) |
| `-speakers` board file | `dts/...-speakers.dts` | Same hardware as the default board (kept so an old `DEBONDRAGON_DTB` still boots). Upstream gets one board file |
| Config fragment (`kernel/debondragon.config`) | distro kernel config | Distro configuration. Checked against linux-next `arch/arm64/configs/defconfig`: every driver of the verified hardware is enabled there directly or selected by one that is, except `MMC_SDHCI_PCI` (BayHub SD reader, untested; an `arm64: defconfig` patch once it's verified). The rest (tethering, DP AUX chardev, lockup detectors, EC module) is DebOnDragon's choice |
| Kernel command line `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` | GRUB | **Temporary workaround**, must be understood and dropped (§4, B2) |
| `video=HDMI-A-1:d` for old kernels | GRUB | Workaround for broken DTBs; obsolete once the fixed DT is upstream |
| EC driver blacklist (`qcom_hamoa_ec`) | modprobe.d | The EC node must not go upstream (protocol mismatch, §4, B8) |

Userspace and packaging (belong outside the kernel):

| Item | Upstream project |
|---|---|
| UCM profile (HiFi: speakers, headphones, headset mic, DMICs) | alsa-ucm-conf (`ucm2/Qualcomm/x1e80100/`, DMI match in `x1e80100.conf`) |
| DSP topology (`...-tplg.bin`, today a renamed T14s topology) | linux-firmware (`qcom/x1e80100/LENOVO/83N3/`) |
| Device-signed ADSP/CDSP/GPU firmware | Not redistributable; stays in the user's Windows partition (`debondragon-firmware`) |
| GRUB devicetree entries, per-kernel DTB sync, HDMI switch, brightness save/restore | Distribution integration (Debian: DTB handling in GRUB / flash-kernel); DebOnDragon-only meanwhile |

## 2. Hardware status per DT node (DebOnDragon kernel -4)

| Function | DT node(s) | Status |
|---|---|---|
| Boot, CPU, RAM, NVMe | purwa.dtsi, pcie6a | Verified |
| eDP panel + GPU | mdss_dp3, panel `edp-panel` (EDID CMN 0x1567 "N153JCN-ELK"), gpu zap | Verified |
| Backlight | pmk8550 PWM ch0, PMC8380 GPIO 4/10 | Verified (control); restore is userspace |
| Keyboard, touchscreen | i2c9 0x3a (TLMM 67), i2c8 0x10 (TLMM 51) | Verified |
| Touchpad | i2c19 0x15, **TLMM 19** level-low, pull-up | Verified (v0.3.0) |
| HDMI | mdss_dp2 → usb_1_ss2 QMP DP (**data-lanes <3 2 1 0>**) → Parade PS176 → connector | Video + extended desktop verified (v0.4.0); hotplug/teardown not yet |
| Camera | usb_2 + PTN3222 (i2c5 0x4b, reset TLMM 7) | Verified |
| Wi-Fi / Bluetooth | WCN7850 pcie4 / uart14 | Verified / partial |
| USB-A | usb_mp | Verified |
| USB-C port 1 | usb_1_ss0, smb2360 SID 0x7 | Controller up; retimers absent, role switch/alt mode broken |
| USB-C port 2 | usb_1_ss1 | Never probes (repeater PMIC SID 0xa absent; 0xb suspected) |
| Headset codec | WCD9385, class-AB headphone playback | Headphones verified on series 5 (v0.4.0) |
| Internal mics | VA macro (`MIC BIAS3` + `VA MIC BIAS1`) | In the profile; not confirmed |
| Speakers | 2× WSA8845 on swr0 (`SpkrLeft`/`SpkrRight`); swr3 off | Front Left verified on series 5. Front Right is dead on this unit in Windows too (hardware) |
| Volume keys | QTEC0001 events on the `a84000` typing-keyboard node | System `debondragon-volkeys` (support 0.5.0) reads it as root and ignores non-volume keys. `uaccess` only for a split consumer node. Not confirmed |
| Thermal sensors | tsens | Verified. Series 6 adds 75 °C CPU passive trips and an 85 °C GPU passive trip |
| EC / fan | i2c5 0x76, "Temp to EC" register 0x20 | Not the Hamoa EC protocol. Userspace reporter is opt-in and unconfirmed; not for upstream yet |
| Suspend/resume | - | Untested |

## 3. What an upstream board file must look like

Our DT compiles against linux-next and passes all 61 `check-dtb.sh`
assertions there, but it is not in upstreamable form:

- **It includes `x1-crd.dtsi`** (another board) and deletes what the 83N3
  doesn't have (third USB-C port, retimers, PMIC SID 0xa, i2c0
  touchpad, ...). Reviewers expect a standalone
  `x1p42100-lenovo-ideapad-slim3-15q8x10.dts` that includes only the SoC
  and PMIC dtsi files and describes exactly the populated hardware.
  Including the CRD also pulls in whatever the CRD gains later (the DTB is
  already 6 KB larger against linux-next).
- **One board file.** The two WSA8845 are already in DebOnDragon's default
  board. Upstream should take that description only after a SoundWire bind
  log from the 83N3 confirms the parts. The `-speakers` file is not a
  second board.
- **Compatible strings** must be documented: `lenovo,ideapad-slim3-15q8x10`
  is not in `Documentation/devicetree/bindings/arm/qcom.yaml` (the
  x1p42100 laptop enum next to `lenovo,thinkbook-16`).
- **HDMI bridge compatible:** the chip is a Parade PS176 (DPCD branch OUI
  00-1C-F8, ID `176GB0`); `realtek,rtd2171` is wrong. Upstream has no
  `parade,ps176`; add it to `simple-bridge.yaml` and `simple-bridge.c`.
  ACPI describes no supply or enable GPIO for it.
- **No EC node**, no CRD leftovers disabled by status, no DebOnDragon
  comments about earlier kernel series.
- **Copyright:** much of the board description is adapted from
  `x1-crd.dtsi` (Qualcomm Innovation Center) and
  `x1p42100-lenovo-thinkbook-16.dts` (Qualcomm, Linaro, Jens Glathe).
  Those notices must be carried over; ours has none. License stays
  BSD-3-Clause like the other Qualcomm board files.

## 4. Blockers, in order

- **B1. Standalone board DTS** written from the evidence in
  `docs/board-notes.md`, then `make dtbs_check` and `dt_binding_check`
  clean on linux-next (needs a full tree and dtschema; not run yet).
- **B2. Boot without `clk_ignore_unused pd_ignore_unused
  regulator_ignore_unused`.** Upstream laptops don't need them. Find the
  clocks, power domains and regulators (so far: VREG_EDP_3P3, VBL9) that
  lose their consumer during boot, describe the consumers in DT, then test
  boots without each argument. Risk: black screen during the test; needs
  a one-time GRUB edit, not a default change.
- **B3. HDMI stability:** hotplug and unplug with active video, reboot
  with HDMI active (`docs/hdmi-testing.md`), before claiming HDMI upstream.
- **B4. USB-C:** describe both ports as built (no retimers; second port's
  repeater PMIC), verify data, charging and orientation on hardware.
- **B5. Audio:** speakers and headphones are verified on series 5 (Front
  Right on this unit is a hardware fault). Still confirm the headset and
  internal mics. The card `model` is still
  37 characters (ALSA truncates the id to 31); UCM is installed under the
  DMI long name and under that truncated id. A mainline board should use a
  model of at most 31 characters. HDMI audio needs a topology with
  DisplayPort graphs; the renamed T14s file does not have them. Then the
  alsa-ucm-conf and linux-firmware topology submissions.
- **B6. Panel:** a panel-edp entry for CMN 0x1567 "N153JCN-ELK" needs
  power-sequencing delays from a datasheet or a justified conservative set;
  until then panel-edp's generic fallback works with a warning.
- **B7. Suspend/resume** test.
- **B8. EC:** leave out until its protocol is known from ACPI evidence.
- **B9. Author identity:** upstream patches need a real name and a working
  email address (the repository uses a GitHub noreply address).

## 5. Patch series plan (none prepared yet)

Base: the current Qualcomm ARM64 tree (`arm64-for-next`) or linux-next.
Each series: `checkpatch.pl --strict`, `make W=1 dtbs dtbs_check`,
`make dt_binding_check DT_SCHEMA_FILES=...`, hardware test report, `b4`
for the cover letter and recipients.

| Series | Patches | Recipients (`get_maintainer.pl`, linux-next) | Depends on |
|---|---|---|---|
| A. HDMI bridge | 1. `dt-bindings: display: bridge: simple-bridge: Add Parade PS176`  2. `drm/bridge: simple-bridge: Add Parade PS176` | Andrzej Hajda, Neil Armstrong, Robert Foss, Laurent Pinchart, Jonas Karlman, Jernej Skrabec, Luca Ceresoli (DRM bridge); DRM misc maintainers; Rob Herring, Krzysztof Kozlowski, Conor Dooley (bindings); dri-devel, devicetree, linux-kernel | - |
| B. Board | 1. `dt-bindings: arm: qcom: Add Lenovo IdeaPad Slim 3 15Q8X10`  2. `arm64: dts: qcom: Add Lenovo IdeaPad Slim 3 15Q8X10` | Bjorn Andersson, Konrad Dybcio, Abel Vesa (Qualcomm); Rob Herring, Krzysztof Kozlowski, Conor Dooley; linux-arm-msm, devicetree, linux-kernel | A (for `parade,ps176`), B1, B2 |
| C. Panel (optional) | `drm/panel-edp: Add CMN N153JCN-ELK` | Douglas Anderson, Neil Armstrong, Jessica Zhang, DRM misc; dri-devel | B6 |
| D. Userspace | alsa-ucm-conf profile; linux-firmware topology | alsa-project (GitHub), linux-firmware (GitLab) | B5 |

Later, only with hardware evidence: the audio userspace submission (B5) and USB-C fixes (B4).

There are no generic driver fixes yet. The DisplayPort reset after failed
link training (series 2) is a possible msm DP bug, but it hasn't been
reproduced or analyzed on the working DT, so it isn't a patch candidate.

## 6. Authorship and AI-assistance rules

From linux-next `Documentation/process/coding-assistants.rst` and
`generated-content.rst`:

- An AI assistant must **not** add `Signed-off-by`. The human submitter
  reviews everything, certifies the DCO with their own `Signed-off-by` and
  must be able to explain and defend every line.
- Tool-assisted patches carry `Assisted-by: LLM [tools]`, and the cover
  letter says what the tool produced and how it was tested.
- Maintainers may scrutinize such patches more or reject them; small,
  well-tested, well-explained patches are the way in.

The DebOnDragon repository's `Co-Authored-By` trailers are fine for this
project but are not the kernel format.
