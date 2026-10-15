#!/bin/bash
# Build debondragon-support_<version>_all.deb from support/root.
# It carries the boot integration (DTB hooks, GRUB devicetree entries,
# kernel command line) and the diagnostic tools, so installed systems get
# fixes to them with a package upgrade instead of a reinstall.
# Usage: support/build-support-deb.sh <outdir> <linux-firmware staging dir>
#   (the staging dir is what iso/fetch-firmware.sh produces)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
out=$1
fw=$2
pkg=$(mktemp -d)
trap 'rm -rf "$pkg"' EXIT

cp -a "$here/support/root/." "$pkg/"
# Set modes explicitly: a checkout on NTFS (e.g. built from WSL or a dual
# boot) shows every file as executable, and systemd warns about that.
find "$pkg" -type d -exec chmod 755 {} +
find "$pkg" -type f -exec chmod 644 {} +
chmod 755 "$pkg"/usr/local/sbin/* "$pkg"/etc/grub.d/* \
          "$pkg"/etc/kernel/postinst.d/* "$pkg"/etc/kernel/postrm.d/*

# Audio topology for the 83N3's two sound card names (default and -SPK),
# from linux-firmware (redistributable; licence files alongside).
tplg=$fw/qcom/x1e80100/LENOVO/21N1/X1E80100-LENOVO-Thinkpad-T14s-tplg.bin
test -f "$tplg" || { echo "missing $tplg" >&2; exit 1; }
install -d "$pkg/usr/lib/firmware/qcom/x1e80100" "$pkg/usr/share/doc/debondragon-support"
for card in X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10 X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10-SPK; do
	install -m 0644 "$tplg" "$pkg/usr/lib/firmware/qcom/x1e80100/$card-tplg.bin"
done
cp "$fw"/licenses/* "$pkg/usr/share/doc/debondragon-support/"
mkdir -p "$pkg/DEBIAN"

cat > "$pkg/DEBIAN/control" <<EOF
Package: debondragon-support
Version: $SUPPORT_VERSION
Architecture: all
Maintainer: DebOnDragon <noreply@users.noreply.github.com>
Section: admin
Priority: optional
Depends: grub-common, dpkg (>= 1.17), alsa-ucm-conf (>= 1.2.14), python3
Recommends: i2c-tools, usbutils, pciutils, pulseaudio | pipewire-pulse, alsa-utils
Description: Lenovo IdeaPad Slim 3 15Q8X10 (83N3) boot integration and tools
 Keeps one devicetree per DebOnDragon kernel in /boot/dtb, loads it from
 GRUB (default entries use the newest kernel's devicetree; a "DebOnDragon
 kernels" submenu boots any installed kernel with its own), sets the kernel
 command line the 83N3 needs, keeps the panel brightness across boots and
 hard resets, selects the 83N3 audio profile (speakers, headphones, mics)
 and its DSP topology, reloads PulseAudio when the sound card appears,
 handles the mute and volume keys, and installs debondragon-firmware,
 debondragon-report, debondragon-ec-check and debondragon-bootlog.
EOF

# Files users are expected to edit keep their changes across upgrades.
cat > "$pkg/DEBIAN/conffiles" <<'EOF'
/etc/default/debondragon
/etc/modprobe.d/debondragon-ec.conf
EOF

cat > "$pkg/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
	/usr/local/sbin/debondragon-dtb-sync || true
	if [ -e /boot/grub/grub.cfg ] && command -v update-grub >/dev/null; then
		update-grub
	fi
	systemctl daemon-reload 2>/dev/null || true
	systemctl enable debondragon-backlight-save.timer 2>/dev/null || true
	systemctl --global enable debondragon-volkeys.service 2>/dev/null || true
	if [ -d /run/systemd/system ]; then
		udevadm control --reload 2>/dev/null || true
		systemctl start debondragon-backlight-save.timer 2>/dev/null || true
	fi
fi
EOF
chmod 755 "$pkg/DEBIAN/postinst"

cat > "$pkg/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ]; then
	systemctl disable --now debondragon-backlight-save.timer 2>/dev/null || true
	systemctl --global disable debondragon-volkeys.service 2>/dev/null || true
fi
EOF
chmod 755 "$pkg/DEBIAN/prerm"

mkdir -p "$out"
dpkg-deb --root-owner-group -b "$pkg" "$out/debondragon-support_${SUPPORT_VERSION}_all.deb"
dpkg-deb -I "$out/debondragon-support_${SUPPORT_VERSION}_all.deb" | sed -n '1,6p'
