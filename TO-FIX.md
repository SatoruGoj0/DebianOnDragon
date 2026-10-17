# DebOnDragon follow-up work

Observed on the Lenovo IdeaPad Slim 3 15Q8X10 (83N3), most recently with
`7.2.0-debondragon-13`. This is the short, actionable backlog for things that
are broken, unsupported, or still need hardware verification. The README is
the user-facing support matrix; keep the evidence and likely cause here.

## Kernel/config gaps

### Linux cannot create or reorder UEFI boot entries

- **Symptom:** installation needs the Windows `Add-DebianBootEntry.ps1`
  helper; Linux cannot update the firmware boot variables on this machine.
- **Likely cause:** the required Qualcomm secure-execution/QSEECOM path is not
  enabled or supported for the 83N3.
- **Fix to investigate:** identify the secure-call/UEFI-variable dependency
  on X1P and compare it with laptops where `efibootmgr` works. Keep the Windows
  helper until writes are proven safe.

## Firmware and accelerator gaps

### FFmpeg's V4L2 encoder crashes; GStreamer encoding works

- **Working:** GStreamer 1.26.5's `v4l2h264enc` and `v4l2h265enc` each
  encoded 90 generated 1280x720 NV12 frames through the Iris encoder. FFprobe
  read all 90 frames from both outputs, software decode of the H.264 output
  completed, and the kernel logged no Iris error. The encoder was
  `/dev/video3` on this boot, but video node numbering can change.
- **Symptom:** Ubuntu FFmpeg 7.1.1's `h264_v4l2m2m` selects `iris_driver`,
  negotiates NV12 input and H.264 output, then segfaults before producing its
  first frame. The output is empty.
- **Cause boundary:** the crash backtrace reaches `memcpy` from libavcodec's
  V4L2 frame-submission path below `avcodec_send_frame`. Since the same kernel,
  firmware, format and encoder work through GStreamer without a kernel error,
  this is an FFmpeg V4L2 userspace interoperability bug, not evidence that the
  hardware encoder or Iris firmware is broken.
- **Fix to investigate:** reproduce against current upstream FFmpeg, identify
  the NV12/multiplanar copy assumption, and send a minimal reproducer and
  backtrace upstream. Until fixed, use GStreamer's V4L2 encoders.

### Low-resolution HEVC can fault the Iris firmware session

- **Working:** forced V4L2 mem2mem tests decode all 90 frames of 1280x720
  H.264 and HEVC samples, and all 30 frames of a 640x360 VP9 sample, through
  `iris_driver`. The decoder was `/dev/video0` on the latest boot, but video
  node numbering changes when the camera and Iris register in a different
  order.
- **Symptom:** a 640x360 8-bit HEVC Main sample produces one corrupt frame,
  then the kernel logs `session error received 0x4000003: fatal error`. Iris
  should be unloaded/reloaded after this failure. The same codec and encoder
  settings work for all 90 frames at 1280x720 after a clean reload.
- **Likely cause:** an Iris firmware/driver buffer constraint at smaller HEVC
  resolutions. Linux 7.2 already contains the upstream increase of
  `H265D_MAX_SLICE` from 1200 to 3600 (commit `3e0b20537516`), so that known
  scratch-buffer fix is not sufficient here.
- **Fix to investigate:** find the minimum failing dimensions, reproduce with
  GStreamer and direct `v4l2-ctl`, compare the firmware buffer requirements
  with current upstream Iris, and report the exact stream plus error upstream.
  AV1 is advertised by the driver but this FFmpeg build has no
  `av1_v4l2m2m` wrapper, so it is also unverified.

### Moonlight needs a libplacebo host-pointer guard

- **Symptom:** Moonlight 6.1.0 segfaults during its startup decoder probe after
  Iris successfully decodes a 1280x720 HEVC frame. The backtrace enters
  `pl_map_avframe_ex()` and calls address zero from libplacebo's Vulkan buffer
  import path. This is userspace, not an Iris firmware crash; the kernel logs
  no session error.
- **Cause:** Ubuntu 25.10 ships libplacebo 7.349.0, which can try host-pointer
  import when `vkGetMemoryHostPointerPropertiesEXT` is unavailable. Upstream
  commit `6eaaa9a68be5` adds the missing capability check.
- **Current workaround:** an ABI-compatible 7.349.0 build with that three-line
  backport is installed in `/usr/local/lib/aarch64-linux-gnu`. Moonlight then
  keeps the Vulkan renderer, selects `hevc_v4l2m2m`, and stays running. Setting
  `VK_DRIVER_FILES=/nonexistent` also avoids the crash and still permits Iris
  decode through Moonlight's SDL renderer, but disables Vulkan for that process.
- **Reproduce:** install the build dependencies listed at the top of
  `scripts/build-libplacebo-hotfix.sh`, run that script, then install the
  resulting `out/debondragon-libplacebo-hotfix_*.deb`. Removing that package
  restores Ubuntu's library after `ldconfig`.
- **Fix to finish:** package the backport reproducibly or move to a distro
  libplacebo release containing the upstream check, then remove the local
  override. Also test a real Moonlight H.264 and HEVC streaming session, not
  only its built-in decoder probe.

### CDSP is not available

- **Symptom:** ADSP attaches and battery status works, but CDSP reports
  `reset broken and remoteproc not running during boot, exiting`.
- **Cause:** unlike ADSP, UEFI did not leave CDSP running. The board currently
  selects attach-only `qcom,broken-reset`, because PAS reset is rejected from
  bare metal, so Linux cannot start a stopped CDSP.
- **Fix to investigate:** determine whether a safe CDSP start path exists,
  whether UEFI can be made to leave it running, or whether CDSP should remain
  disabled until secure-monitor support exists. Do not remove
  `qcom,broken-reset` and retry resets blindly.

## Ports and peripherals

### Second USB-C port and USB-C role/alt-mode support

- **Symptoms:** `a800000.usb` and `fd9000.phy` remain deferred; the expected
  repeater's smb2360 at SPMI SID `0xa` is absent. Both PS883x retimers at I2C
  address `0x08` fail to answer (`-6`), PMIC alt mode cannot acquire a retimer
  switch, and UCSI eventually reports `PPM init failed`.
- **Likely cause:** the CRD wiring inherited by the DT does not match this
  board. SID `0xb` may be the second port's repeater, and the retimers may be
  different parts or at different addresses.
- **Fix to investigate:** decode the Windows ACPI/PEP and driver configuration
  for both physical ports, identify the actual repeater/retimer wiring, and
  replace the inherited CRD nodes. Test USB 2/3 in both plug orientations,
  charging/role switching, then DisplayPort alt mode.

### HDMI audio is absent

- **Symptom:** HDMI video works, but there is no HDMI playback path.
- **Cause:** the borrowed T14s AudioReach topology has no DisplayPort audio
  graphs, and the DT deliberately removes the DP audio links.
- **Fix:** obtain or build an 83N3 topology with the correct DP graph, restore
  only the matching DAI link, and test without regressing internal audio.

### The attached ADSP does not expose its audio GPR channel

- **Symptom:** on series 11 and 13, `/proc/asound/cards` is empty. The ADSP is
  attached and battery telemetry works, but the LPI pin controller, SoundWire
  controllers and `snd-x1e80100` card remain deferred.
- **Cause boundary:** UEFI's running ADSP publishes `IPCRTR`,
  `PMIC_RTR_ADSP_APPS` and several diagnostic GLINK channels, but not the
  devicetree's `adsp_apps` channel. Consequently the APR/GPR bus has no
  devices, the Q6PRM LPASS clock provider never appears, and the LPI pinctrl
  probe cannot acquire its `core`/`audio` clocks. This exact state was already
  present on series 11, so it is not caused by the series-13 thermal merge.
- **Known history:** speaker and headphone playback worked with the series-5
  audio DT/UCM setup. Microphones remain unconfirmed.
- **Fix to investigate:** determine how Windows or the vendor firmware starts
  the AVS audio protection domain and makes `adsp_apps` available; compare a
  Windows-to-Linux warm boot with a Linux reboot and inspect service-registry/
  `pd-mapper` activation. Do not try to reset the attached ADSP: PAS reset is
  rejected on this machine.

### EC temperature reporting is experimental; fan control is unverified

- **Symptom:** `qcom-hamoa-ec` reports an invalid/zero fan count and asks for a
  firmware update; the read-only probe showed that this EC does not implement
  the upstream Hamoa EC command set.
- **Cause boundary:** that driver has the wrong protocol and remains
  blacklisted. Windows instead reports die temperature to register `0x20` and
  leaves the embedded controller in charge of its own fan curve.
- **Series-13 result:** all CPU/CPUSS zones expose a 75 °C passive trip and all
  GPU zones expose an 85 °C passive trip. Support 0.5.0's opt-in
  `debondragon-fan` status command reads the zones and fan registers, but the
  reporter has not been enabled. It never writes an RPM target.
- **Fix/validation:** test opt-in reporting under load, suspend/resume and power
  off as documented in `docs/hardware-testing.md`; derive and review the full
  83N3 protocol before attempting direct fan control. Keep `qcom-hamoa-ec`
  blacklisted.

### Fingerprint reader is unsupported

- **State:** no verified device identity, bus mapping or Linux driver is in
  the board description.
- **Next check:** identify it from Windows/USB/ACPI data, then determine
  whether a libfprint-supported driver exists.

## Verification still needed

- **Browser use of Iris:** direct V4L2 H.264 decode is verified with FFmpeg,
  and Chromium launches after reconnecting its stale `gpu-2404` snap content
  mount. Confirm a browser video actually selects the Iris decoder node; this is a
  browser/userspace integration check, not a missing kernel codec driver.

- **Suspend/resume:** test suspend, wake, repeated cycles, Wi-Fi reconnect,
  audio, battery updates and display recovery. Collect `debondragon-report`
  after a failure.
- **SD reader:** the O2 Micro `1217:8621` controller binds to `sdhci-pci` and
  creates `mmc0`, but card insertion/read/write has not been tested.
- **USB throughput:** USB-A works, but SuperSpeed rate has not been measured;
  USB-C data needs the port-by-port tests above.
- **HDMI lifecycle:** video and extended desktop work; still test boot with a
  monitor attached, hotplug/unplug/replug and long runs.
- **GRUB console workaround:** support 0.4.1 selects `GRUB_TERMINAL=console`
  to avoid GOP input lag. Confirm the next packaged-support boot has responsive
  keyboard navigation before marking it fully verified.
- **SCMI OPP warning:** firmware twice rejects adding NCC1 level 2956800 with
  `-16`. No user-visible failure is linked to it yet; investigate only if CPU
  performance/power measurements show a problem.
