#!/bin/bash
# Build the live root filesystem: Debian + DebOnDragon kernel + firmware +
# board integration. Runs as root on arm64 Debian.
# Usage: iso/build-rootfs.sh <workdir>   (expects <workdir>/kernel-debs)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
root=$work/rootfs

in_root() { chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 "$@"; }

unmount_all() {
	for m in run dev/pts dev sys proc; do
		mountpoint -q "$root/$m" && umount -l "$root/$m"
	done
	return 0
}
trap unmount_all EXIT

unmount_all
rm -rf "$root"
debootstrap --arch=arm64 --variant=minbase "$DEBIAN_SUITE" "$root" "$DEBIAN_MIRROR"

rm -f "$root/etc/apt/sources.list"
cat > "$root/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: $DEBIAN_MIRROR
Suites: $DEBIAN_SUITE $DEBIAN_SUITE-updates
Components: main contrib non-free non-free-firmware

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $DEBIAN_SUITE-security
Components: main contrib non-free non-free-firmware
EOF

mount -t proc proc "$root/proc"
mount -t sysfs sys "$root/sys"
mount --bind /dev "$root/dev"
mount --bind /dev/pts "$root/dev/pts"
mount -t tmpfs tmpfs "$root/run"

# No services start inside the build chroot.
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"

echo debondragon > "$root/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tdebondragon\n::1\tlocalhost ip6-localhost ip6-loopback\n' > "$root/etc/hosts"

# Board integration first, so the kernel's postinst hooks find it.
cp -a "$here/iso/overlay/." "$root/"
chmod 755 "$root/etc/kernel/postinst.d/dtb-debondragon" \
          "$root/etc/grub.d/01_debondragon" \
          "$root/usr/local/sbin/debondragon-firmware" \
          "$root/usr/local/sbin/debondragon-report" \
          "$root/usr/local/sbin/debondragon-bootlog"

in_root apt-get update
# confold: keep our overlay versions of conffiles (e.g. initramfs modules).
grep -vE '^[[:space:]]*(#|$)' "$here/iso/packages.list" | xargs \
	chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
	apt-get install -y -o Dpkg::Options::=--force-confold

# Only acts when the kernel command line has "debondragon.log".
in_root systemctl enable debondragon-bootlog.service

sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' "$root/etc/locale.gen"
in_root locale-gen
in_root update-locale LANG=en_US.UTF-8

mkdir -p "$root/tmp/kernel"
cp "$work"/kernel-debs/linux-image-*.deb "$root/tmp/kernel/"
in_root sh -c 'dpkg -i /tmp/kernel/linux-image-*.deb'
rm -rf "$root/tmp/kernel"

"$here/iso/fetch-firmware.sh" "$work" "$root/usr/lib/firmware"

kver=$(cat "$work/kernel-debs/RELEASE")
test -f "$root/boot/dtb/debondragon.dtb" || { echo "board dtb was not installed" >&2; exit 1; }
# Our Calamares packages.conf must survive calamares-settings-debian's
# conffile; Debian's version aborts the install (apt-get error 100).
grep -q try_remove "$root/etc/calamares/modules/packages.conf" ||
	{ echo "Calamares packages.conf override was replaced" >&2; exit 1; }
in_root update-initramfs -u -k "$kver"

in_root apt-get clean
rm -rf "$root"/var/lib/apt/lists/* "$root/usr/sbin/policy-rc.d" "$root"/var/log/*.log
: > "$root/etc/machine-id"
rm -f "$root/var/lib/dbus/machine-id"

unmount_all
du -sh "$root"
