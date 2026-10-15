#!/bin/bash
# Behaviour tests for debondragon-support, run against a fake /sys and fake
# config files (no root, nothing on the running system is touched):
#   - debondragon-backlight: restore/save rules
#   - /etc/default/grub.d/debondragon.cfg: text terminal, kernel command line,
#     GRUB default, Windows Boot Manager (os-prober) kept
#   - the UCM long-name file selects the 83N3 profile, which drives speakers
#     when the amps are bound and headphones in class-AB
# Usage: scripts/test-support.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
root=$here/support/root
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
expect() { # description, actual, expected
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi
}

# --- debondragon-backlight -------------------------------------------------
mkdir -p "$tmp/sys/backlight" "$tmp/var"
sed -e "s|/sys/class/backlight|$tmp/sys|" -e "s|/var/lib/debondragon|$tmp/var|" \
    -e "s|/etc/default/debondragon|$tmp/default|g" \
    "$root/usr/local/sbin/debondragon-backlight" > "$tmp/bl"
bl() { sh "$tmp/bl" "$@" >/dev/null 2>&1; }
bri() { cat "$tmp/sys/backlight/brightness"; }
echo 4095 > "$tmp/sys/backlight/max_brightness"
: > "$tmp/default"

echo 204 > "$tmp/sys/backlight/brightness"; bl restore
expect "no saved level: raised to the 30% default" "$(bri)" 1228
echo 100 > "$tmp/sys/backlight/brightness"; bl save
expect "save stores the current level" "$(cat "$tmp/var/backlight-backlight")" 100
touch -d '2000-01-01' "$tmp/var/backlight-backlight"
old_mtime=$(stat -c %Y "$tmp/var/backlight-backlight")
bl save
expect "unchanged level is not rewritten" "$(stat -c %Y "$tmp/var/backlight-backlight")" \
	"$old_mtime"
echo 204 > "$tmp/sys/backlight/brightness"; bl restore
expect "saved low level restored exactly (deliberate setting kept)" "$(bri)" 100
echo 0 > "$tmp/sys/backlight/brightness"; bl save
expect "level 0 (panel off) is not saved" "$(cat "$tmp/var/backlight-backlight")" 100
echo 9999 > "$tmp/var/backlight-backlight"; echo 500 > "$tmp/sys/backlight/brightness"; bl restore
expect "saved level above max is ignored" "$(bri)" 1228
rm "$tmp/var/backlight-backlight"
echo DEBONDRAGON_MIN_BRIGHTNESS=0 > "$tmp/default"; echo 50 > "$tmp/sys/backlight/brightness"; bl restore
expect "minimum 0 disables the raise" "$(bri)" 50
echo DEBONDRAGON_MIN_BRIGHTNESS=abc > "$tmp/default"; bl restore
expect "invalid minimum is rejected" "$?" 1

# --- GRUB snippet and kernel submenu ----------------------------------------
# Fake /boot with DebOnDragon kernels; the scripts read /boot/dtb and /boot.
fakeboot() { # releases...: (re)create $tmp/boot with these kernels
	rm -rf "${tmp:?}/boot"; mkdir -p "$tmp/boot/dtb"
	for r in "$@"; do
		: > "$tmp/boot/dtb/debondragon-$r.dtb"
		: > "$tmp/boot/vmlinuz-$r"; : > "$tmp/boot/initrd.img-$r"
	done
}
sed -e "s|/etc/default/debondragon|$tmp/default|g" -e "s|/boot/|$tmp/boot/|g" \
    "$root/etc/default/grub.d/debondragon.cfg" > "$tmp/grub.cfg"
grubvars() { # prints default|cmdline|os-prober for the current $tmp/default
	(GRUB_DEFAULT=0; GRUB_CMDLINE_LINUX=""; . "$tmp/grub.cfg"
	 echo "$GRUB_DEFAULT|${GRUB_CMDLINE_LINUX# }|$GRUB_DISABLE_OS_PROBER")
}
base="clk_ignore_unused pd_ignore_unused regulator_ignore_unused"
off="video=HDMI-A-1:d"
cp "$root/etc/default/debondragon" "$tmp/default"
expect "GRUB uses the responsive firmware text console" \
	"$(GRUB_CMDLINE_LINUX=""; . "$tmp/grub.cfg"; echo "$GRUB_TERMINAL")" console
expect "shipped defaults are DEBONDRAGON_HDMI=auto" "$(grep -c '^DEBONDRAGON_HDMI=auto$' "$tmp/default")" 1
fakeboot 7.2.0-debondragon-3 7.2.0-debondragon-4
expect "auto, newest kernel -4: HDMI on, Debian default entry, Windows kept" "$(grubvars)" "0|$base|false"
fakeboot 7.2.0-debondragon 7.2.0-debondragon-2 7.2.0-debondragon-3
expect "auto, newest kernel -3 (old lane mapping): HDMI off" "$(grubvars)" "0|$base $off|false"
fakeboot 7.2.0-debondragon-4 7.2.0-debondragon-10
expect "auto, series 10 counts as newer than 4" "$(grubvars)" "0|$base|false"
echo DEBONDRAGON_HDMI=off >> "$tmp/default"; fakeboot 7.2.0-debondragon-4
expect "DEBONDRAGON_HDMI=off: HDMI off even with -4" "$(grubvars)" "0|$base $off|false"
echo DEBONDRAGON_HDMI=on >> "$tmp/default"; fakeboot 7.2.0-debondragon-3
expect "DEBONDRAGON_HDMI=on: no video= even with -3" "$(grubvars)" "0|$base|false"
printf 'DEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-3\n' > "$tmp/default"; fakeboot 7.2.0-debondragon-3 7.2.0-debondragon-4
expect "DEBONDRAGON_DEFAULT_KERNEL pins the submenu entry" "$(grubvars)" \
	"debondragon-kernels>debondragon-7.2.0-debondragon-3|$base|false"
rm "$tmp/default"
expect "no defaults file: auto" "$(grubvars)" "0|$base|false"

# Kernel submenu, with grub-mkconfig_lib stubbed out.
sed -e "s|/etc/default/debondragon|$tmp/default|g" -e "s|/boot/|$tmp/boot/|g" \
    -e 's|^\. /usr/share/grub/grub-mkconfig_lib$|prepare_grub_to_access_device() { :; }; make_system_path_relative_to_its_root() { echo "$1"; }|' \
    "$root/etc/grub.d/42_debondragon_kernels" > "$tmp/42"
submenu() { # DEBONDRAGON_HDMI value -> "id: args" per entry
	printf 'DEBONDRAGON_DTB=x.dtb\nDEBONDRAGON_HDMI=%s\n' "$1" > "$tmp/default"
	GRUB_DEVICE_UUID=u GRUB_CMDLINE_LINUX="$base $off" grub_probe="echo x #" sh "$tmp/42" 2>/dev/null |
		awk '/menuentry/ { for (i=1;i<=NF;i++) if ($i=="--id") id=$(i+1) }
		     /linux / { v = ($0 ~ /video=HDMI-A-1:d/) ? "off" : "on"; print id ": " v }'
}
fakeboot 7.2.0-debondragon-3 7.2.0-debondragon-4
expect "submenu auto: -4 on, -4 fallback off, -3 off" "$(submenu auto | tr '\n' ' ')" \
	"debondragon-7.2.0-debondragon-4: on debondragon-7.2.0-debondragon-4-hdmi-off: off debondragon-7.2.0-debondragon-3: off "
expect "submenu off: every entry off" "$(submenu off | tr '\n' ' ')" \
	"debondragon-7.2.0-debondragon-4: off debondragon-7.2.0-debondragon-3: off "
expect "submenu has the id GRUB_DEFAULT uses" \
	"$(grep -c -- "--id debondragon-kernels" "$root/etc/grub.d/42_debondragon_kernels")" 1

# --- UCM -------------------------------------------------------------------
ucm=$root/usr/share/alsa/ucm2/conf.d/x1e80100/LENOVO-83N3-IdeaPadSlim315Q8X10-LNVNB161216.conf
hifi=$root/usr/share/alsa/ucm2/Qualcomm/x1e80100/DebOnDragon-IdeaPad-HiFi.conf
card=$root/usr/share/alsa/ucm2/conf.d/x1e80100/X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10.conf
expect "UCM long-name file exists" "$([ -f "$ucm" ] && echo yes)" yes
expect "long-name file selects the 83N3 card profile" \
	"$(grep -c 'X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10.conf' "$ucm")" 1
expect "truncated card name has a profile" \
	"$([ -f "$root/usr/share/alsa/ucm2/conf.d/x1e80100/X1E80100-LENOVO-IdeaPad-Slim3-1.conf" ] && echo yes)" yes
expect "headphones use class-AB, not the ULP mode" \
	"$(grep -c "RX HPH Mode' CLS_AB_LOHIFI" "$hifi")" 1
# grep -c prints one count per file. Sum them; print 0 when nothing matches.
grepc() { grep -h -c "$@" | awk '{ s += $1 } END { print s + 0 }'; }
expect "ULP headphone mode is not selected" "$(grepc CLS_H_ULP "$hifi" "$card")" 0
expect "speaker path is present" "$(grep -c 'SectionDevice."Speaker"' "$hifi")" 1
expect "speaker PA volume stays within the kernel limit of 6" \
	"$(grep -c "PA Volume' 6" "$hifi")" 2
expect "WSA digital volume stays within the kernel limit of 81" \
	"$(grep -c "Digital Volume' 81" "$card")" 2
expect "no DisplayPort mixer writes (absent from the T14s topology)" \
	"$(grepc DISPLAY_PORT "$hifi" "$card")" 0
expect "speakers are skipped when the amp controls are absent" \
	"$(grepc "Control \"name='SpkrLeft PA Volume'\"" "$hifi" "$card")" 2

# --- Device-signed firmware helpers ----------------------------------------
firmware=$root/usr/local/sbin/debondragon-firmware
expect "Linux firmware helper requires the authenticated Iris PA firmware" \
	"$(sed -n '/^required=(/,/)/p' "$firmware" | grep -c 'qcvss8380_pa.mbn')" 1
expect "Linux firmware helper selects PA image at the series-10 path" \
	"$(grep -c 'install -m 0644.*qcvss8380_pa.mbn.*qcvss8380.mbn' "$firmware")" 1
expect "Windows helper exports the authenticated Iris PA firmware" \
	"$(grep -c "'qcvss8380_pa.mbn'" "$here/windows/Export-Firmware.ps1")" 1
expect "Windows helper does not export the rejected non-PA Iris image" \
	"$(grep -c "'qcvss8380.mbn'" "$here/windows/Export-Firmware.ps1" || true)" 0

exit $fail
