# DebOnDragon follow-up work

Observed on the Lenovo IdeaPad Slim 3 15Q8X10 (83N3), most recently with
`7.2.0-debondragon-10`. This is the short, actionable backlog for things that
are broken, unsupported, or still need hardware verification. The README is
the user-facing support matrix; keep the evidence and likely cause here.

## Kernel/config gaps

### Docker networking cannot start

- **Symptom:** `docker.service` exits while creating its `DOCKER` NAT chain:
  `iptables: Failed to initialize nft: Protocol not supported`.
- **Cause:** the kernel has containers' basic requirements (`CGROUPS`,
  namespaces, seccomp, bridge, veth and overlayfs), but has
  `CONFIG_NF_TABLES=n` and `CONFIG_NF_NAT=n`. Debian's `iptables` uses the nft
  backend, so Docker cannot create its bridge/NAT rules.
- **Fix to try:** enable `CONFIG_NF_TABLES`, `CONFIG_NF_NAT` and the relevant
  nftables NAT/masquerade modules in `kernel/debondragon.config`; add them to
  `kernel/check-config.sh`; rebuild; then run a container with outbound
  networking. Do not treat a daemon started with `--iptables=false` as the
  final fix.

### Linux cannot create or reorder UEFI boot entries

- **Symptom:** installation needs the Windows `Add-DebianBootEntry.ps1`
  helper; Linux cannot update the firmware boot variables on this machine.
- **Likely cause:** the required Qualcomm secure-execution/QSEECOM path is not
  enabled or supported for the 83N3.
- **Fix to investigate:** identify the secure-call/UEFI-variable dependency
  on X1P and compare it with laptops where `efibootmgr` works. Keep the Windows
  helper until writes are proven safe.

## Firmware and accelerator gaps

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

### Series-10 audio needs regression testing

- **State:** speakers and headphones were verified with series 5. Series 10
  inherits those WSA8845 and UCM changes, but has not been regression-tested
  after the DSP handoff and video changes. Microphones remain unconfirmed.
- **Next check:** inspect
  `/sys/bus/soundwire/devices` and `/proc/asound/cards`, then follow the
  moderate-volume tests in `docs/hardware-testing.md`.

### EC fan reporting/control is unsupported

- **Symptom:** `qcom-hamoa-ec` reports an invalid/zero fan count and asks for a
  firmware update; the read-only probe showed that this EC does not implement
  the upstream Hamoa EC command set.
- **Cause:** protocol mismatch, not evidence that the fan itself is broken;
  the embedded controller still manages the fan autonomously.
- **Fix to investigate:** derive the 83N3 protocol from ACPI/Windows behavior
  before enabling any writes. Keep the driver blacklisted in normal installs.

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
