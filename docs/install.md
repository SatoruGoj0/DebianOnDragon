# Installing DebOnDragon on the IdeaPad Slim 3 15Q8X10 (83N3)

## Before you start (in Windows)

1. **Save your BitLocker recovery key.** Turning off Secure Boot makes Windows
   ask for it on the next Windows boot. Find it at
   <https://account.microsoft.com/devices/recoverykey> or with
   `manage-bde -protectors -get C:` in an admin terminal. Keep a copy off the laptop.
2. **Back up your data.** Installing Linux means repartitioning the SSD.
3. **Make space for Linux** (dual boot): Disk Management → right-click C: →
   *Shrink Volume*. 40 GB or more is a good start. Leave the space unallocated.
4. **Export the device firmware** to a second USB stick or any folder you can
   reach from Linux. In PowerShell, from this repository:
   ```powershell
   .\windows\Export-Firmware.ps1 -Destination E:\debondragon-firmware
   ```
   This only reads from Windows. You can skip it if Windows isn't BitLocker-encrypted.
   In that case `debondragon-firmware` can read the files straight from the Windows partition.

## Write the ISO to a USB stick

Download `debondragon-trixie-arm64.iso` and `SHA256SUMS` from the
[Releases page](https://github.com/SatoruGoj0/DebianOnDragon/releases). Then
check the hash: `Get-FileHash .\debondragon-trixie-arm64.iso` should match
`SHA256SUMS`.

Write it with **Rufus**. When Rufus asks, choose **"Write in DD Image mode"**.
ISO mode will not boot. On Linux, `dd` works:

```bash
sudo dd if=debondragon-trixie-arm64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## Firmware settings

1. Reboot and press **F2** (or use the Novo button) to open BIOS setup.
2. **Security → Secure Boot → Disabled.** GRUB has to load a devicetree, and
   signed Secure Boot GRUB doesn't allow that.
3. Save and exit, then press **F12** for the boot menu and choose the USB stick.

Plug the stick into the **USB-A port**. USB-C ports depend on firmware that
isn't loaded until later.

## Boot menu

- **DebOnDragon live + installer**: the normal entry.
- **safe graphics**: use this if the screen goes black. It keeps the firmware
  framebuffer and doesn't load the msm display driver.
- **verbose boot log**: shows kernel messages. Take a photo of the screen when
  reporting problems.
- **Fallback devicetrees**: other X1P laptops, only for debugging.

The live session logs in automatically (user `user`, password `live`).

## Install

1. Double-click **Install Debian** on the desktop.
2. At *Partitions*, choose **Install alongside** or **Manual partitioning**, using
   the unallocated space. **Don't choose "Erase disk"** unless you want to remove
   Windows. Reuse the existing EFI system partition (mount point `/boot/efi`,
   don't format it).
3. Finish and reboot. GRUB shows Debian and Windows Boot Manager.

## After installing: device firmware

Log in, then:

```bash
# From the folder Export-Firmware.ps1 created (plug in that USB stick):
sudo debondragon-firmware /media/$USER/<stick>/debondragon-firmware
# or let it search an unencrypted Windows partition:
sudo debondragon-firmware
```

Reboot. This enables battery status, USB-C, GPU acceleration and the DSPs.
The audio DSP is one of those files: without it the sound card never
appears. `debondragon-firmware` with no arguments finds a Windows
partition that is already mounted. `debondragon-firmware --help` prints
the usage.

## If something doesn't work

If the screen goes black after the boot messages, reboot and pick **safe
graphics**. Plug in a FAT/exFAT USB stick (it mounts automatically in the
desktop), open a terminal and run:

```bash
sudo debondragon-report
```

It saves a text file to the stick with the kernel log and the display,
backlight and PMIC state. Open an issue with that file and say which boot
entry you used.

## Going back to Windows only

In BIOS, set the boot order to Windows Boot Manager (or delete the `debian` boot
entry). Then delete the Linux partitions in Disk Management. Re-enable Secure Boot.
