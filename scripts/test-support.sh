#!/bin/bash
# Behaviour tests for debondragon-support, run against a fake /sys and fake
# config files (no root, nothing on the running system is touched):
#   - debondragon-backlight: restore/save rules
#   - /etc/default/grub.d/debondragon.cfg: kernel command line, GRUB default,
#     Windows Boot Manager (os-prober) kept
#   - the UCM long-name dispatcher points at both board profiles
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
touch -d '2000-01-01' "$tmp/var/backlight-backlight"; bl save
expect "unchanged level is not rewritten" "$(stat -c %Y "$tmp/var/backlight-backlight")" \
	"$(date -d '2000-01-01' +%s)"
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

# --- GRUB snippet ------------------------------------------------------------
sed "s|/etc/default/debondragon|$tmp/default|g" "$root/etc/default/grub.d/debondragon.cfg" > "$tmp/grub.cfg"
grubvars() { # prints default|cmdline|os-prober for the current $tmp/default
	(GRUB_DEFAULT=0; GRUB_CMDLINE_LINUX=""; . "$tmp/grub.cfg"
	 echo "$GRUB_DEFAULT|${GRUB_CMDLINE_LINUX# }|$GRUB_DISABLE_OS_PROBER")
}
base="clk_ignore_unused pd_ignore_unused regulator_ignore_unused"
cp "$root/etc/default/debondragon" "$tmp/default"
expect "shipped defaults: HDMI off, Debian default entry, Windows kept" \
	"$(grubvars)" "0|$base video=HDMI-A-1:d|false"
echo DEBONDRAGON_HDMI=on >> "$tmp/default"
expect "DEBONDRAGON_HDMI=on drops video=HDMI-A-1:d" "$(grubvars)" "0|$base|false"
printf 'DEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-2\n' > "$tmp/default"
expect "DEBONDRAGON_DEFAULT_KERNEL pins the submenu entry" "$(grubvars)" \
	"debondragon-kernels>debondragon-7.2.0-debondragon-2|$base video=HDMI-A-1:d|false"
rm "$tmp/default"
expect "no defaults file: HDMI still off" "$(grubvars)" "0|$base video=HDMI-A-1:d|false"
expect "submenu has the id GRUB_DEFAULT uses" \
	"$(grep -c -- "--id debondragon-kernels" "$root/etc/grub.d/42_debondragon_kernels")" 1
expect "entries have the id GRUB_DEFAULT uses" \
	"$(grep -c -- '--id debondragon-$release' "$root/etc/grub.d/42_debondragon_kernels")" 1

# --- UCM -------------------------------------------------------------------
ucm=$root/usr/share/alsa/ucm2/conf.d/x1e80100/LENOVO-83N3-IdeaPadSlim315Q8X10-LNVNB161216.conf
expect "UCM long-name file exists" "$([ -f "$ucm" ] && echo yes)" yes
expect "UCM dispatcher includes the default and -SPK profiles" \
	"$(grep -cE 'X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10(-SPK)?\.conf' "$ucm")" 2
expect "default UCM profile touches no speaker (WSA) controls" \
	"$(cat "$root/usr/share/alsa/ucm2/conf.d/x1e80100/X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10.conf" \
	       "$root/usr/share/alsa/ucm2/Qualcomm/x1e80100/DebOnDragon-IdeaPad-HiFi.conf" |
	   grep -v '^ *#' | grep -ci 'wsa')" 0

exit $fail
