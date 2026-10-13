# Kernel upgrades, rollback and building from source

Kernel updates for an installed DebOnDragon system are two Debian packages.
You never need to reinstall Debian.

| Package | What it is |
|---|---|
| `linux-image-7.2.0-debondragon-N_..._arm64.deb` | The kernel, its modules and its devicetrees |
| `debondragon-support_X.Y.Z_all.deb` | Boot integration (per-kernel devicetrees, GRUB entries, kernel command line) and tools (`debondragon-firmware`, `-report`, `-ec-check`, `-bootlog`) |
| `linux-headers-...deb` | Optional; only for building out-of-tree modules (DKMS) |

## How kernels are kept apart

Each kernel series has its own release name: `7.2.0-debondragon` (v0.1.x),
`7.2.0-debondragon-2` (v0.2.0), and so on. Installing a new one **adds** it next
to the old one: the old kernel, its modules and its devicetree stay installed.

- `/boot/dtb/debondragon-<release>.dtb`: the devicetree that came with each kernel
- `/boot/dtb/debondragon.dtb`: a copy of the **newest** kernel's devicetree

GRUB uses them like this:

- **Debian GNU/Linux** and **Advanced options** (Debian's normal entries) load
  `debondragon.dtb`, i.e. the newest devicetree, for whichever kernel you pick.
- **DebOnDragon kernels (each with its own devicetree)**: one entry per
  installed kernel, each with *its own* devicetree. Use this to roll back.

## Upgrade from v0.3.0 (HDMI)

You have kernel -3 (maybe also -4 from testing) and support 0.2.1, with
`DEBONDRAGON_DEFAULT_KERNEL` pinned. Keep -3 as the default until the HDMI
tests in `docs/hdmi-testing.md` pass.

1. Install support 0.3.0 and kernel -4 (skip the kernel if it's already
   installed). `--force-confold` keeps your edited
   `/etc/default/debondragon` instead of asking:
   ```bash
   sudo apt install -o Dpkg::Options::=--force-confold ./debondragon-support_0.3.0_all.deb ./linux-image-7.2.0-debondragon-4_*_arm64.deb
   ```
2. Your file still says `DEBONDRAGON_HDMI=off` from 0.2.1. Switch it to
   `auto` (HDMI on only for kernels with the verified fix; -3 stays off):
   ```bash
   sudo sed -i 's/^DEBONDRAGON_HDMI=.*/DEBONDRAGON_HDMI=auto/' /etc/default/debondragon
   sudo update-grub
   ```
3. Check the entries:
   ```bash
   sudo grep -m1 'set default=' /boot/grub/grub.cfg       # ...debondragon-7.2.0-debondragon-3
   for id in 7.2.0-debondragon-4 7.2.0-debondragon-4-hdmi-off 7.2.0-debondragon-3; do printf '%s: ' $id; sudo awk -v id="--id debondragon-$id {" 'index($0,id){f=1} f&&/^[[:space:]]*linux /{print (/video=HDMI-A-1:d/ ? "HDMI off" : "HDMI on"); exit}' /boot/grub/grub.cfg; done
   ```
   Expected: `-4: HDMI on`, `-4-hdmi-off: HDMI off`, `-3: HDMI off`.
4. Run the tests in `docs/hdmi-testing.md`, then make -4 the default as
   described there.

## Test a new kernel once, keeping the current one as default (recommended)

Use this for any kernel that hasn't been confirmed on hardware yet. The
example installs `7.2.0-debondragon-3` while `7.2.0-debondragon-2` stays the
default. Needs `debondragon-support` 0.2.1 or later.

1. **Install the support package alone**, reboot once, and check that the
   current kernel still works as before:
   ```bash
   sudo apt install ./debondragon-support_0.2.1_all.deb
   ```
2. **Pin the known-good kernel** as the GRUB default:
   ```bash
   sudo sed -i '/^DEBONDRAGON_DEFAULT_KERNEL=/d' /etc/default/debondragon
   echo 'DEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-2' | sudo tee -a /etc/default/debondragon
   sudo update-grub
   ```
   `update-grub` must print `DebOnDragon default kernel: 7.2.0-debondragon-2`.
   Check:
   ```bash
   sudo grep -m1 'set default=' /boot/grub/grub.cfg
   ```
   It shows `debondragon-kernels>debondragon-7.2.0-debondragon-2`.
3. **Install the new kernel** (it installs beside the old one):
   ```bash
   sudo apt install ./linux-image-7.2.0-debondragon-3_*_arm64.deb
   ls /boot/vmlinuz-* /boot/dtb/
   ```
   Both kernels and `debondragon-7.2.0-debondragon-2.dtb` /
   `debondragon-7.2.0-debondragon-3.dtb` must be there, and `update-grub` must
   still print `DebOnDragon default kernel: 7.2.0-debondragon-2`.
4. **Boot the new kernel once:**
   ```bash
   sudo grub-reboot 'debondragon-kernels>debondragon-7.2.0-debondragon-3'
   sudo reboot
   ```
   GRUB clears this request as it boots, so the boot after it is the pinned
   kernel again. If the new kernel hangs or the screen stays dark, hold the
   power button for 10 seconds and switch on again: you're back on -2.
5. **After the test boot**, check `uname -r` (`7.2.0-debondragon-3`) and that
   the one-time request was used up:
   ```bash
   sudo grub-editenv list
   ```
   `next_entry` must be empty or absent.
6. **Make it the default** only once it has proved itself:
   ```bash
   sudo sed -i 's/^DEBONDRAGON_DEFAULT_KERNEL=.*/DEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-3/' /etc/default/debondragon
   sudo update-grub
   ```
   Keep -2 installed as the rollback.

## Upgrade

1. Download from the [Releases page](https://github.com/SatoruGoj0/DebianOnDragon/releases)
   the `linux-image-...deb`, the `debondragon-support_...deb` and `SHA256SUMS`, into one folder.
2. Check the downloads:
   ```bash
   sha256sum -c --ignore-missing SHA256SUMS
   ```
   Every `.deb` you downloaded must be listed with `OK`. A file that isn't
   listed at all was **not** checked (`--ignore-missing` skips names it
   can't find); don't install it.
3. Install both in one command (order doesn't matter; the support package
   refreshes the devicetrees and GRUB itself):
   ```bash
   sudo apt install ./debondragon-support_*_all.deb ./linux-image-7.2.0-debondragon-*_arm64.deb
   ```
   apt runs the kernel's hooks: it builds the initramfs, copies the kernel's
   devicetree to `/boot/dtb`, and regenerates `grub.cfg`.
4. Check before rebooting:
   ```bash
   ls /boot/dtb/
   grep -E "^menuentry|submenu|devicetree" /boot/grub/grub.cfg | head -20
   ```
   You should see a `debondragon-<release>.dtb` for every installed kernel, and
   the "DebOnDragon kernels" submenu.
5. Reboot. The default entry starts the newest kernel. Check with `uname -r`.

The previous kernel isn't touched. Keep it until the new one has proved itself.

## Roll back

**For one boot:** in the GRUB menu, open **DebOnDragon kernels (each with its
own devicetree)** and choose the older kernel. It boots with the devicetree it
was built with.

If the GRUB menu doesn't show, hold **Shift** or press **Esc** while GRUB
starts, or make the menu always visible:
```bash
echo 'GRUB_TIMEOUT_STYLE=menu' | sudo tee /etc/default/grub.d/menu.cfg
echo 'GRUB_TIMEOUT=5' | sudo tee -a /etc/default/grub.d/menu.cfg
sudo update-grub
```

**For good:** boot the older kernel, then remove the newer one:
```bash
sudo apt remove linux-image-7.2.0-debondragon-2
```
The removal hook deletes that kernel's devicetree, points `debondragon.dtb`
back at the newest remaining kernel, and regenerates GRUB.

Never remove the kernel you are running, or the last kernel.

**If nothing boots:** start the live USB, then mount and chroot into the
installed system:
```bash
sudo mount /dev/nvme0n1pX /mnt            # your Debian root partition
sudo mount /dev/nvme0n1p1 /mnt/boot/efi   # the EFI partition
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done
sudo chroot /mnt
apt remove linux-image-7.2.0-debondragon-2   # inside the chroot
```
Find the partitions with `lsblk -f`. Debian's root is the large `ext4` one.

## What the upgrade does not touch

- The Windows EFI files and its fallback loader (`\EFI\Boot\bootaa64.efi`)
- The UEFI boot entries (Linux can't write them on this laptop anyway)
- Partitions
- Your existing kernels

## Build from source

On any arm64 Debian 13 system as root (WSL works, so does the laptop itself),
or in Docker:

```bash
git clone https://github.com/SatoruGoj0/DebianOnDragon.git
cd DebianOnDragon
docker run --rm --privileged -v "$PWD:/src" -w /src -e PACKAGES_ONLY=1 debian:trixie ./build.sh
```

`PACKAGES_ONLY=1` builds the kernel and support packages without the ISO. The
packages land in `out/`. The kernel build takes about 25 minutes on 4 cores
and runs the config, devicetree and module checks described in the README.

To make a new kernel series, raise `KERNEL_PKGREV` in `build.conf`. A build
with the same series replaces that series' package on upgrade, instead of
installing beside it.
