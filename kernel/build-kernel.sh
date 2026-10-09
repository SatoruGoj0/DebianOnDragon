#!/bin/bash
# Build the DebOnDragon kernel as Debian packages, with the 83N3 devicetree.
# Runs natively on arm64 Debian. Usage: kernel/build-kernel.sh <workdir>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
src=$work/linux
mkdir -p "$work/kernel-debs"

if [ ! -f "$src/Makefile" ]; then
  git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$src"
  # Without git metadata, setlocalversion adds no "-dirty"/"+" suffix for
  # our added devicetree, so the release is exactly 7.2.0-debondragon.
  rm -rf "$src/.git"
fi

# Add our board next to the upstream ones.
cp "$here"/dts/*.dts "$src/arch/arm64/boot/dts/qcom/"
mk=$src/arch/arm64/boot/dts/qcom/Makefile
for dts in "$here"/dts/*.dts; do
  dtb=$(basename "${dts%.dts}").dtb
  grep -q "$dtb" "$mk" || echo "dtb-\$(CONFIG_ARCH_QCOM)	+= $dtb" >> "$mk"
done

cd "$src"
make ARCH=arm64 defconfig
scripts/kconfig/merge_config.sh -m .config "$here/kernel/debondragon.config"
make ARCH=arm64 olddefconfig

# Report fragment options that did not survive olddefconfig (e.g. a
# missing dependency), so a silent drop shows up in the build log.
while IFS= read -r line; do
  case $line in CONFIG_*=*) grep -qxF "$line" .config || echo "warning: $line not applied" ;; esac
done < "$here/kernel/debondragon.config"

version=$(make -s kernelversion)
make -j"$(nproc)" ARCH=arm64 INSTALL_MOD_STRIP=1 \
  KDEB_PKGVERSION="$version-1~debondragon" KDEB_CHANGELOG_DIST="$DEBIAN_SUITE" bindeb-pkg

mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$work/kernel-debs/"
rm -f "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_* "$work"/*.buildinfo "$work"/*.changes

# The kernel release (uname -r) is whatever the image package was built as.
image=$(ls "$work"/kernel-debs/linux-image-*.deb | grep -v -- -dbg_ | head -1)
kver=$(basename "$image"); kver=${kver#linux-image-}; kver=${kver%%_*}
echo "$kver" > "$work/kernel-debs/RELEASE"
echo "kernel release: $kver"
ls -l "$work/kernel-debs"
