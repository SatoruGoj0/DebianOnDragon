# DebOnDragon follow-up work

Observed on the Lenovo IdeaPad Slim 3 15Q8X10 (83N3), most recently with
`7.2.0-debondragon-7`. This is the short, actionable backlog for things that
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

### Snap applications, including local browsers, cannot start

- **Symptom:** Chromium is reported as a broken snap, installing Firefox fails
  while mounting its snap, and the mount units report a bad filesystem. The
  kernel log gives the decisive error: `Filesystem uses "lzo" compression.
  This is not supported`.
- **Cause:** the kernel enables SquashFS with XZ and Zstd, but not
  `CONFIG_SQUASHFS_LZO`. Several installed Ubuntu snap images are
  LZO-compressed, so snapd cannot mount them. This is separate from the GPU
  firmware failure; a browser may still need software rendering after it can
  be mounted.
- **Fix:** enable `CONFIG_SQUASHFS_LZO=y` in `kernel/debondragon.config`, assert
  it in `kernel/check-config.sh`, rebuild and reboot. Then reload systemd and
  refresh or reinstall the broken snaps. Verify Chromium/Firefox launch with
  software rendering before testing hardware acceleration.

### Linux cannot create or reorder UEFI boot entries

- **Symptom:** installation needs the Windows `Add-DebianBootEntry.ps1`
  helper; Linux cannot update the firmware boot variables on this machine.
- **Likely cause:** the required Qualcomm secure-execution/QSEECOM path is not
  enabled or supported for the 83N3.
- **Fix to investigate:** identify the secure-call/UEFI-variable dependency
  on X1P and compare it with laptops where `efibootmgr` works. Keep the Windows
  helper until writes are proven safe.

## Firmware and accelerator gaps

### GPU acceleration fails with the firmware currently installed

- **Symptom:** `/dev/dri` exists, but the boot log repeatedly reports
  `error -22 initializing firmware .../qcdxkmsucpurwa.mbn` and
  `gpu hw init failed: -22`.
- **Cause:** the installed file is the generic X1P `gen71500_zap.mbn` copied
  under the Lenovo filename. The secure monitor rejects it; the 83N3 needs
  its exact signed `qcdxkmsucpurwa.mbn` from the Windows Qualcomm display
  driver package.
- **Fix:** obtain the exact file from this model's Windows DriverStore (or the
  matching official driver package), install it with `debondragon-firmware`,
  rebuild the initramfs and reboot. Verify with `dmesg`, `glxinfo -B` or
  `vulkaninfo`; merely having a render node is not sufficient.

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

### Internal speakers, headphones and microphones need hardware testing

- **State:** current `main` describes the two WSA8845 amplifiers and revised
  UCM paths, but this merged audio version has not yet been boot-tested here.
  The older boot showed SoundWire/sound-card deferred probes.
- **Next check:** boot a package built from current `main`, inspect
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
