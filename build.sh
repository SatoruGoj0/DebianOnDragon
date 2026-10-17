#!/bin/bash
# Build the DebOnDragon ISO end to end. Runs as root on arm64 Debian 13:
# natively, in WSL, or in the debian:trixie container that CI uses:
#
#   docker run --rm --privileged -v "$PWD:/src" -w /src debian:trixie ./build.sh
#
# Output: out/<name>.iso and out/SHA256SUMS. Set REBUILD_KERNEL=1 to rebuild
# a kernel that is already in work/kernel-debs.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${WORK:-$here/work}
out=${OUT:-$here/out}

if [ "$(dpkg --print-architecture)" != arm64 ]; then
	echo "build.sh must run on arm64 (the rootfs is assembled with chroot)" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
	git ca-certificates build-essential bc bison flex libssl-dev libelf-dev \
	dpkg-dev debhelper rsync kmod cpio python3 xz-utils zstd libdw-dev curl \
	debootstrap squashfs-tools xorriso mtools dosfstools device-tree-compiler \
	grub-common grub-efi-arm64-bin

mkdir -p "$work" "$out"
if [ "${REBUILD_KERNEL:-0}" = 1 ] || [ ! -f "$work/kernel-debs/RELEASE" ]; then
	rm -rf "$work/kernel-debs"
	"$here/kernel/build-kernel.sh" "$work"
fi
rm -rf "$work/support-deb" "$work/fw-staging"
"$here/iso/fetch-firmware.sh" "$work" "$work/fw-staging"
"$here/support/build-support-deb.sh" "$work/support-deb" "$work/fw-staging"

# Packages for upgrading an installed system (docs/kernel-upgrade.md).
cp "$work"/kernel-debs/linux-image-*.deb "$work"/kernel-debs/linux-headers-*.deb \
   "$work"/support-deb/debondragon-support_*_all.deb "$out/"
# GitHub release assets can't contain "~" (it publishes 7.2.0-3~debondragon
# as 7.2.0-3.debondragon). Name the files as they will be published, so
# SHA256SUMS matches the downloads; the package version inside is unchanged.
for f in "$out"/*~*.deb; do
	[ -e "$f" ] && mv -f "$f" "${f//\~/.}"
done
[ "${PACKAGES_ONLY:-0}" = 1 ] && exit 0

"$here/iso/build-rootfs.sh" "$work"
"$here/iso/build-image.sh" "$work" "$out"
