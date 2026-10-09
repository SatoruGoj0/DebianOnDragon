#!/bin/bash
# Build the DebOnDragon kernel as Debian packages, with the 83N3 devicetree.
# Runs natively on arm64 Debian. Usage: kernel/build-kernel.sh <workdir>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
src=$work/linux
mkdir -p "$work/kernel-debs"

if [ ! -d "$src/.git" ]; then
  git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$src"
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

kver=$(make -s kernelrelease)
make -j"$(nproc)" ARCH=arm64 INSTALL_MOD_STRIP=1 \
  KDEB_PKGVERSION="${kver%%-*}-1~debondragon" bindeb-pkg

mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$work/kernel-debs/"
rm -f "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_* "$work"/*.buildinfo "$work"/*.changes
echo "$kver" > "$work/kernel-debs/RELEASE"
ls -l "$work/kernel-debs"
