#!/bin/bash
# Assert the 83N3-specific facts in a compiled board DTB, so a regression in
# the DTS (or in the upstream dtsi it builds on) fails the build.
# Usage: scripts/check-dtb.sh <board.dtb>
set -uo pipefail
dtb=$1
fail=0
dts=$(dtc -I dtb -O dts "$dtb" 2>/dev/null)

prop() { fdtget -t "${3:-s}" "$dtb" "$1" "$2" 2>/dev/null; }
expect() { # description, actual, expected
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi
}
node_status() { # "missing" if the node doesn't exist, else its status (default okay)
	local s
	fdtget -l "$dtb" "$1" >/dev/null 2>&1 || { echo missing; return; }
	s=$(prop "$1" status); echo "${s:-okay}"
}

expect "model" "$(prop / model)" "Lenovo IdeaPad Slim 3 15Q8X10"
expect "backlight is pwm-backlight" "$(prop /backlight compatible)" "pwm-backlight"
pmk=$(fdtget -t x "$dtb" /soc@0/arbiter@c400000/spmi@c42d000/pmic@0/pwm phandle 2>/dev/null)
pwm=$(fdtget -t x "$dtb" /backlight pwms 2>/dev/null)
expect "backlight uses pmk8550 PWM channel 0" "${pwm% *}" "$pmk 0"
expect "touchpad IRQ pull-up" "$(echo "$dts" | grep -A4 'tpad-default-state' | grep -c 'bias-pull-up')" "1"
expect "no CRD retimer-2 supplies (TLMM 126)" "$(echo "$dts" | grep -c 'VREG_RTMR2')" "0"
expect "HDMI bridge present" "$(prop /hdmi-bridge compatible)" "realtek,rtd2171"
expect "HDMI hot-plug pin uses usb2_dp" "$(echo "$dts" | grep -A3 'hdmi-hpd-default-state' | grep -c 'usb2_dp')" "1"
expect "dp2 (HDMI) enabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae9a000)" "okay"
expect "dp0 disabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae90000)" "disabled"
expect "dp1 disabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae98000)" "disabled"
expect "eDP (dp3) enabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@aea0000)" "okay"
expect "camera eUSB2 repeater" "$(echo "$dts" | grep -c 'redriver@4b {')" "1"
expect "audio card enabled" "$(node_status /sound)" "okay"
expect "audio card model" "$(prop /sound model)" "X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10"
expect "no speaker link in default board" "$(fdtget -l "$dtb" /sound 2>/dev/null | grep -c wsa-dai-link)" "0"
expect "no DP audio links (dp0/dp1 off)" "$(fdtget -l "$dtb" /sound 2>/dev/null | grep -c displayport)" "0"
# Fixed paths, not labels: kernel-built DTBs have no __symbols__ table.
expect "speaker SoundWire (swr0) off" "$(node_status /soc@0/soundwire@6b10000)" "disabled"
expect "headset SoundWire (swr1) on" "$(node_status /soc@0/soundwire@6ad0000)" "okay"

exit $fail
