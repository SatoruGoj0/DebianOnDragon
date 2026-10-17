#!/bin/bash
# Behaviour tests for debondragon-support, run against a fake /sys and fake
# config files (no root, nothing on the running system is touched):
#   - debondragon-backlight: restore/save rules
#   - /etc/default/grub.d/debondragon.cfg and 02_debondragon_default: text
#     terminal, kernel command line, first/default entry, Windows kept
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
expect "DEBONDRAGON_DEFAULT_KERNEL pins the first top-level entry" "$(grubvars)" \
	"debondragon-default|$base|false"
rm "$tmp/default"
expect "no defaults file: auto" "$(grubvars)" "0|$base|false"

# First/default entry and kernel submenu, with grub-mkconfig_lib stubbed out.
sed -e "s|/etc/default/debondragon|$tmp/default|g" -e "s|/boot/|$tmp/boot/|g" \
    -e 's|^\. /usr/share/grub/grub-mkconfig_lib$|prepare_grub_to_access_device() { :; }; make_system_path_relative_to_its_root() { echo "$1"; }|' \
    "$root/etc/grub.d/02_debondragon_default" > "$tmp/02"
default_entry() {
	GRUB_DEVICE_UUID=u GRUB_CMDLINE_LINUX="$base $off" GRUB_CMDLINE_LINUX_DEFAULT=quiet \
		grub_probe="echo x #" sh "$tmp/02" 2>/dev/null
}
fakeboot 7.2.0-debondragon-3 7.2.0-debondragon-4
printf 'DEBONDRAGON_DTB=x.dtb\nDEBONDRAGON_HDMI=auto\nDEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-4\n' > "$tmp/default"
first=$(default_entry)
expect "top-level default has the stable GRUB id" \
	"$(printf '%s\n' "$first" | grep -c -- '--id debondragon-default')" 1
expect "top-level default loads the pinned kernel and its DTB" \
	"$(printf '%s\n' "$first" | grep -Ec 'vmlinuz-7\.2\.0-debondragon-4|debondragon-7\.2\.0-debondragon-4\.dtb')" 2
expect "top-level series 4 default enables HDMI" \
	"$(printf '%s\n' "$first" | grep -c "$off" || true)" 0
printf 'DEBONDRAGON_DTB=x.dtb\nDEBONDRAGON_DEFAULT_KERNEL=7.2.0-debondragon-99\n' > "$tmp/default"
expect "missing pinned kernel does not create a broken top-level entry" \
	"$(default_entry | wc -l)" 0

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
expect "rollback submenu has a stable GRUB id" \
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
expect "support package accepts Ubuntu 25.10 alsa-ucm-conf" \
	"$(grep -c 'alsa-ucm-conf (>= 1.2.12)' "$here/support/build-support-deb.sh")" 1
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
fw=$root/usr/local/sbin/debondragon-firmware
expect "Linux firmware helper requires the authenticated Iris PA firmware" \
	"$(sed -n '/^required=(/,/)/p' "$fw" | grep -c 'qcvss8380_pa.mbn')" 1
expect "Linux firmware helper selects PA image at the series-10 path" \
	"$(grep -c 'install -m 0644.*qcvss8380_pa.mbn.*qcvss8380.mbn' "$fw")" 1
expect "Windows helper exports the authenticated Iris PA firmware" \
	"$(grep -c "'qcvss8380_pa.mbn'" "$here/windows/Export-Firmware.ps1")" 1
expect "Windows helper does not export the rejected non-PA Iris image" \
	"$(grep -c "'qcvss8380.mbn'" "$here/windows/Export-Firmware.ps1" || true)" 0
help=$(DEBONDRAGON_FIRMWARE_DRY=1 "$fw" --help)
expect "firmware --help exits 0" "$?" 0
expect "firmware --help is usage text" "$(printf '%s\n' "$help" | grep -c 'Usage: debondragon-firmware')" 1
win=$tmp/win
store=$win/Windows/System32/DriverStore/FileRepository/hidi2c
mkdir -p "$store"
for blob in qcadsp8380.mbn adsp_dtbs.elf qccdsp8380.mbn cdsp_dtbs.elf qcdxkmsucpurwa.mbn qcvss8380_pa.mbn; do
	echo x > "$store/$blob"
done
mkdir -p "$tmp/bin"
cat > "$tmp/bin/findmnt" <<EOF
#!/bin/sh
case "\$*" in
*-rno\ TARGET,FSTYPE*) echo '$win ntfs' ;;
*-S*) echo '$win' ;;
*) exit 0 ;;
esac
EOF
cat > "$tmp/bin/lsblk" <<'EOF'
#!/bin/sh
case "$*" in
*NAME,FSTYPE*) echo '/dev/nvme0n1p3 ntfs' ;;
*) exit 0 ;;
esac
EOF
cat > "$tmp/bin/mount" <<'EOF'
#!/bin/sh
echo "mount must not run when the NTFS volume is already mounted: $*" >&2
exit 99
EOF
chmod 755 "$tmp/bin/findmnt" "$tmp/bin/lsblk" "$tmp/bin/mount"
dry=$(PATH="$tmp/bin:$PATH" DEBONDRAGON_FIRMWARE_DRY=1 "$fw")
expect "firmware dry-run finds an already-mounted Windows tree" "$?" 0
expect "firmware dry-run names the DriverStore" \
	"$(printf '%s\n' "$dry" | grep -c "source $win/Windows/System32/DriverStore/FileRepository$")" 1
expect "firmware dry-run would install the ADSP firmware" \
	"$(printf '%s\n' "$dry" | grep -c 'would-install qcadsp8380.mbn')" 1
expect "firmware dry-run would install the authenticated Iris firmware" \
	"$(printf '%s\n' "$dry" | grep -c 'would-install qcvss8380_pa.mbn')" 1
expect "firmware dry-run would select the PA image at the kernel path" \
	"$(printf '%s\n' "$dry" | grep -c 'would-select qcvss8380_pa.mbn as qcvss8380.mbn')" 1

# --- PulseAudio late card --------------------------------------------------
cat > "$tmp/bin/pactl" <<EOF
#!/bin/sh
if [ "\$1" = info ]; then exit 0; fi
printf '%s\n' "\$PACTL_SINKS"
EOF
cat > "$tmp/bin/systemctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> '$tmp/systemctl.log'
exit 0
EOF
chmod 755 "$tmp/bin/pactl" "$tmp/bin/systemctl"
refresh=$root/usr/local/sbin/debondragon-pulse-refresh
: > "$tmp/systemctl.log"
out=$(PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run1" DEBONDRAGON_PULSE_REFRESH_DELAY=0 \
	DEBONDRAGON_PULSE_REFRESH_DRY=1 PACTL_SINKS='0 auto_null module-null-sink.c s16le 2ch 48000Hz SUSPENDED' \
	"$refresh")
expect "pulse refresh restarts when the only sink is auto_null" "$out" restart
out=$(PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run2" DEBONDRAGON_PULSE_REFRESH_DELAY=0 \
	DEBONDRAGON_PULSE_REFRESH_DRY=1 PACTL_SINKS='0 alsa_output.HiFi__Speaker module-alsa-card.c s16le 2ch 48000Hz RUNNING' \
	"$refresh")
expect "pulse refresh leaves a real sink alone" "$out" ""

# --- volume keys -----------------------------------------------------------
expect "volume key mapping" \
	"$(DEBONDRAGON_VOLKEYS_SELFTEST=1 "$root/usr/local/sbin/debondragon-volkeys")" ok
expect "volume keys follow loginctl ActiveSession" \
	"$(grep -c 'loginctl_show' "$root/usr/local/sbin/debondragon-volkeys")" 3
expect "volume keys do not treat ACTIVE=1 as a boolean" \
	"$(grep -c 'ACTIVE_UID' "$root/usr/local/sbin/debondragon-volkeys")" 0
rule=$root/etc/udev/rules.d/72-debondragon-volkeys.rules
expect "volume-key udev rule tags uaccess" "$(grep -c 'TAG+="uaccess"' "$rule")" 1
expect "volume-key udev rule does not assign group input" "$(grep -c 'GROUP=' "$rule")" 0
expect "volume-key udev rule skips the typing keyboard" \
	"$(grep -c 'ENV{ID_INPUT_KEYBOARD}!="1"' "$rule")" 1
expect "volume-key udev rule is limited to the a84000 bus" "$(grep -c 'a84000.i2c' "$rule")" 1
expect "volume keys are a system service" \
	"$(grep -c '^WantedBy=multi-user.target$' "$root/usr/lib/systemd/system/debondragon-volkeys.service")" 1
expect "volume-key user unit is masked" \
	"$(readlink "$root/etc/systemd/user/debondragon-volkeys.service")" /dev/null
expect "volume keys have no user service to start" \
	"$(test ! -e "$root/usr/lib/systemd/user/debondragon-volkeys.service" && echo absent)" absent
expect "volume keys are not wanted by the user session" \
	"$(find "$root/etc/systemd/user/default.target.wants" "$root/etc/xdg/autostart" -name '*volkeys*' 2>/dev/null | wc -l)" 0
expect "volume keys log permission denied without asking for group input" \
	"$(DEBONDRAGON_VOLKEYS_SELFTEST=1 "$root/usr/local/sbin/debondragon-volkeys" >/dev/null && \
		grep -c 'Do not add the user to group input' "$root/usr/local/sbin/debondragon-volkeys")" 1
expect "postinst removes the 0.4.1 user wants link" \
	"$(grep -c 'rm -f /etc/systemd/user/default.target.wants/debondragon-volkeys.service' \
		"$here/support/build-support-deb.sh")" 1
expect "postinst enables the system volume-key service" \
	"$(grep -c 'systemctl enable debondragon-volkeys.service' \
		"$here/support/build-support-deb.sh")" 1

# --- fan temperature report (dry: no i2c, nothing written) -----------------
fan=$root/usr/local/sbin/debondragon-fan
expect "fan help exits 0" "$(DEBONDRAGON_FAN_DRY=1 "$fan" --help >/dev/null; echo $?)" 0
expect "fan unknown option exits 2" "$(DEBONDRAGON_FAN_DRY=1 "$fan" --nope >/dev/null 2>&1; echo $?)" 2
mkdir -p "$tmp/thermal/thermal_zone0" "$tmp/thermal/thermal_zone1" \
	"$tmp/thermal/thermal_zone2" "$tmp/thermal/thermal_zone3"
echo cpu0-0-top-thermal > "$tmp/thermal/thermal_zone0/type"
echo 62600 > "$tmp/thermal/thermal_zone0/temp"
echo gpuss-0-thermal > "$tmp/thermal/thermal_zone1/type"
echo 59400 > "$tmp/thermal/thermal_zone1/temp"
echo pm8550_tz > "$tmp/thermal/thermal_zone2/type"
echo 37000 > "$tmp/thermal/thermal_zone2/temp"
echo qcom-battmgr-bat > "$tmp/thermal/thermal_zone3/type"
echo 30200 > "$tmp/thermal/thermal_zone3/temp"
sample=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_SYS="$tmp/thermal" DEBONDRAGON_FAN_BUS=9 \
	DEBONDRAGON_FAN_ONCE=1 "$fan" run)
expect "fan report uses the hottest cpu/gpu zone, not the PMIC or battery" \
	"$(printf '%s\n' "$sample" | grep -c '^hottest cpu0-0-top-thermal 62600 deci 626$')" 1
expect "fan report is deci-celsius on 0x20 for sensor 0x01 only" \
	"$(printf '%s\n' "$sample" | grep -c '^report 0x20 0x01 0x02 0x72 0x02$')" 1
expect "fan report does not send skin or the reserved sensor" \
	"$(printf '%s\n' "$sample" | grep -c '^report 0x20 0x0[23] ')" 0
expect "fan curve targets fan 1 profile 6 at source 0x01" \
	"$(printf '%s\n' "$sample" | grep -c '^dry 9 w68@0x76 0x28 0x61 0x01 0x40 0x00 0x20 0x19 0x00 ')" 1
expect "fan curve is installed for profiles 1 through 7" \
	"$(printf '%s\n' "$sample" | grep -c '^dry 9 w68@0x76 0x28 0x[1-7]1 0x01 0x40 ')" 7
expect "fan curve caps the top step at 4000 rpm" \
	"$(printf '%s\n' "$sample" | grep -c '0x28 0x69 0x64 0x00$')" 7
expect "fan curve does not program fan 2" \
	"$(printf '%s\n' "$sample" | grep -c '0x28 0x[1-7]2 ')" 0
expect "fan curve does not write debug mode, the profile, trips, or EC enable" \
	"$(printf '%s\n' "$sample" | grep -c -E '0x30|w2@0x76 0x24|0x25|0x35')" 0
expect "fan run reads slot 0x61 back instead of writing it" \
	"$(printf '%s\n' "$sample" | grep -c '^read lut readback fan1 profile 6: w5@0x76 0x28 0x61 0x01 0x00 0x00 r65@0x76$')" 1
expect "fan run clears modern-standby before reporting" \
	"$(printf '%s\n' "$sample" | grep -c '^report 0x23 0x00$')" 1
echo 40000 > "$tmp/thermal/thermal_zone0/temp"
echo 30000 > "$tmp/thermal/thermal_zone1/temp"
sample=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_SYS="$tmp/thermal" DEBONDRAGON_FAN_BUS=9 \
	DEBONDRAGON_FAN_ONCE=1 "$fan" run)
expect "fan report rounds 40.0 °C to 400 decidegrees" \
	"$(printf '%s\n' "$sample" | grep -c '^report 0x20 0x01 0x02 0x90 0x01$')" 1
echo 0 > "$tmp/thermal/thermal_zone0/temp"
echo 0 > "$tmp/thermal/thermal_zone1/temp"
sample=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_SYS="$tmp/thermal" DEBONDRAGON_FAN_BUS=9 \
	DEBONDRAGON_FAN_ONCE=1 "$fan" run 2>/dev/null)
expect "fan report refuses a 0 °C reading" "$(printf '%s\n' "$sample" | grep -c '^report 0x20')" 0
echo 62600 > "$tmp/thermal/thermal_zone0/temp"
sus=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_BUS=9 "$fan" suspend)
expect "fan suspend writes only modern-standby 1" "$sus" "report 0x23 0x01"
res=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_BUS=9 "$fan" resume)
expect "fan resume clears modern-standby" "$res" "report 0x23 0x00"
st=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_SYS="$tmp/thermal" "$fan" status)
expect "fan status names the hottest zone and does not report a write" \
	"$(printf '%s\n' "$st" | grep -c 'hottest: cpu0-0-top-thermal 62600')" 1
expect "fan status dry does not claim an RPM write" \
	"$(printf '%s\n' "$st" | grep -c 'rpm: dry')" 1
probe=$(DEBONDRAGON_FAN_DRY=1 DEBONDRAGON_FAN_SYS="$tmp/thermal" DEBONDRAGON_FAN_BUS=9 "$fan" probe)
expect "fan probe names the decidegree bytes it is already sending" \
	"$(printf '%s\n' "$probe" | grep -c '^hottest: cpu0-0-top-thermal 62600 deci 626 bytes 0x72 0x02$')" 1
expect "fan probe shows the tenths-of-kelvin value without sending it" \
	"$(printf '%s\n' "$probe" | grep -c '^not sent, tenths of kelvin: 3358$')" 1
expect "fan probe reads fan status and the curve" \
	"$(printf '%s\n' "$probe" | grep -c '^read fan1 status 0x21: w2@0x76 0x21 0x01 r1@0x76$')" 1
expect "fan probe reads the fan-1 profile-6 curve" \
	"$(printf '%s\n' "$probe" | grep -c '^read lut fan1 profile 6: w5@0x76 0x28 0x61 0x01 0x00 0x00 r65@0x76$')" 1
expect "fan probe reads every fan-1 profile slot" \
	"$(printf '%s\n' "$probe" | grep -c '^read lut fan1 profile [1-7]: w5@0x76 0x28 0x[1-7]1 ')" 7
expect "fan probe also reads slot 0x61 with a zero second byte" \
	"$(printf '%s\n' "$probe" | grep -c '^read lut fan1 profile 6 arg0: w5@0x76 0x28 0x61 0x00 0x00 0x00 r65@0x76$')" 1
expect "fan probe does not write debug mode or set the curve" \
	"$(printf '%s\n' "$probe" | grep -c -E '0x30|w68@')" 0
expect "fan probe does not write modern-standby or the trip register" \
	"$(printf '%s\n' "$probe" | grep -c -E '0x23|0x25|0x35')" 0
expect "fan probe does not send a temperature report" \
	"$(printf '%s\n' "$probe" | grep -c 'w5@0x76 0x20')" 0

exit $fail
