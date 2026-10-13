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
cp "$here"/dts/*.dts "$here"/dts/*.dtsi "$src/arch/arm64/boot/dts/qcom/"
mk=$src/arch/arm64/boot/dts/qcom/Makefile
for dts in "$here"/dts/*.dts; do
  dtb=$(basename "${dts%.dts}").dtb
  grep -qF "$dtb" "$mk" || echo "dtb-\$(CONFIG_ARCH_QCOM)	+= $dtb" >> "$mk"
done

cd "$src"
make ARCH=arm64 defconfig
# merge_config.sh splits paths on spaces, so merge a copy from the work dir.
cp "$here/kernel/debondragon.config" "$work/debondragon.config"
scripts/kconfig/merge_config.sh -m .config "$work/debondragon.config"
make ARCH=arm64 olddefconfig

# Report fragment options that did not survive olddefconfig (e.g. a
# missing dependency), so a silent drop shows up in the build log.
while IFS= read -r line; do
  case $line in CONFIG_*=*) grep -qxF "$line" .config || echo "warning: $line not applied" ;; esac
done < "$here/kernel/debondragon.config"

"$here/kernel/check-config.sh" .config

# Series > 1 gets its own release suffix so it installs beside older kernels.
series=""
[ "$KERNEL_PKGREV" -gt 1 ] && series="-$KERNEL_PKGREV"
version=$(make -s kernelversion)
make -j"$(nproc)" ARCH=arm64 INSTALL_MOD_STRIP=1 LOCALVERSION="$series" \
  KDEB_PKGVERSION="$version-$KERNEL_PKGREV~debondragon" KDEB_CHANGELOG_DIST="$DEBIAN_SUITE" bindeb-pkg

# The board DTB must still state the facts verified on hardware.
"$here/scripts/check-dtb.sh" "arch/arm64/boot/dts/qcom/$(basename "$BOARD_DTB")"

mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$work/kernel-debs/"
rm -f "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_* "$work"/*.buildinfo "$work"/*.changes

# The kernel release (uname -r) is whatever the image package was built as.
image=""
for deb in "$work"/kernel-debs/linux-image-*.deb; do
  case $deb in *-dbg_*) ;; *) image=$deb; break ;; esac
done
kver=$(basename "$image"); kver=${kver#linux-image-}; kver=${kver%%_*}
echo "$kver" > "$work/kernel-debs/RELEASE"
echo "kernel release: $kver"

# Every driver the board DTB relies on must be in the package, and modules
# must resolve their dependencies.
"$here/kernel/check-modules.sh" "$image" "$kver"
ls -l "$work/kernel-debs"
