#!/bin/bash
# Pack the live root filesystem into a UEFI-bootable hybrid ISO (write it
# to a USB stick as-is, e.g. with Rufus in DD mode or dd).
# Usage: iso/build-image.sh <workdir> <outdir>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
out=$2
root=$work/rootfs
tree=$work/iso-tree
kver=$(cat "$work/kernel-debs/RELEASE")
dtbs=$root/usr/lib/linux-image-$kver/qcom

rm -rf "$tree"
mkdir -p "$tree/live" "$tree/boot/grub" "$tree/EFI/BOOT" "$tree/dtb/qcom" "$out"
touch "$tree/.debondragon"

cp "$root/boot/vmlinuz-$kver" "$tree/live/vmlinuz"
# GRUB on arm64 only boots PE images (CONFIG_EFI_ZBOOT); fail early otherwise.
if [ "$(head -c 2 "$tree/live/vmlinuz")" != MZ ]; then
	echo "vmlinuz is not an EFI (PE) image; GRUB cannot boot it" >&2
	exit 1
fi
cp "$root/boot/initrd.img-$kver" "$tree/live/initrd.img"
cp "$dtbs"/x1p42100-*.dtb "$tree/dtb/qcom/"
test -f "$tree/dtb/$BOARD_DTB"

sed -e "s|@BOOT_ARGS@|$BOOT_ARGS|g" -e "s|@BOARD_DTB@|$BOARD_DTB|g" \
	"$here/iso/grub/grub.cfg.in" > "$tree/boot/grub/grub.cfg"

mksquashfs "$root" "$tree/live/filesystem.squashfs" \
	-noappend -comp xz -Xbcj arm -b 1M -wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*'

grub-mkstandalone -O arm64-efi -o "$work/BOOTAA64.EFI" \
	--modules="part_gpt part_msdos fat iso9660 search configfile normal" \
	"boot/grub/grub.cfg=$here/iso/grub/embedded.cfg"
cp "$work/BOOTAA64.EFI" "$tree/EFI/BOOT/BOOTAA64.EFI"

# EFI system partition image appended to the ISO as a GPT partition.
rm -f "$work/efiboot.img"
truncate -s 16M "$work/efiboot.img"
mkfs.vfat -n EFIBOOT "$work/efiboot.img" >/dev/null
mmd -i "$work/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$work/efiboot.img" "$work/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI

# Writable FAT partition for boot logs (debondragon-bootlog). Windows gives
# it a drive letter automatically, unlike the EFI partition.
rm -f "$work/dodlog.img"
truncate -s 64M "$work/dodlog.img"
mkfs.vfat -n DODLOG "$work/dodlog.img" >/dev/null
printf 'DebOnDragon boot logs are written here when booting with debondragon.log.\r\n' > "$work/README.TXT"
mcopy -i "$work/dodlog.img" "$work/README.TXT" ::/README.TXT

iso=$out/$ISO_NAME.iso
rm -f "$iso"
xorriso -as mkisofs -r -V "$ISO_LABEL" -J -joliet-long -iso-level 3 \
	-partition_offset 16 \
	-append_partition 2 0xef "$work/efiboot.img" \
	-append_partition 3 0x0c "$work/dodlog.img" -appended_part_as_gpt \
	-c boot.catalog -e --interval:appended_partition_2:all:: -no-emul-boot \
	-o "$iso" "$tree"

size=$(stat -c %s "$iso")
echo "ISO: $iso ($((size / 1024 / 1024)) MiB)"
# GitHub release assets are limited to 2 GiB.
if [ "$size" -ge $((2 * 1024 * 1024 * 1024)) ]; then
	echo "ISO is too large for a GitHub release asset" >&2
	exit 1
fi
(cd "$out" && sha256sum "$(basename "$iso")" > SHA256SUMS)
cat "$out/SHA256SUMS"
