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
# Touchpad interrupt: DSDT GpioInt 0x3c0 = TLMM 19, Level, ActiveLow
# (IRQ_TYPE_LEVEL_LOW = 8), on every touchpad variant at i2c19.
tlmm=$(fdtget -t x "$dtb" /soc@0/pinctrl@f100000 phandle 2>/dev/null)
i2c19=/soc@0/geniqup@8c0000/i2c@88c000
for tp in touchpad@15 touchpad@2c touchpad@38 touchpad@5d; do
	expect "$tp IRQ on TLMM 19, level-low" "$(fdtget -t x "$dtb" "$i2c19/$tp" interrupts-extended 2>/dev/null)" "$tlmm 13 8"
done
expect "touchpad pinctrl pin is gpio19" "$(echo "$dts" | grep -A4 'tpad-default-state' | grep -c 'pins = "gpio19"')" "1"
# The CRD's own touchpad (TLMM 3) sits on i2c0, which must stay off.
expect "CRD touchpad bus i2c0 disabled" "$(node_status /soc@0/geniqup@bc0000/i2c@b80000)" "disabled"
expect "no enabled touchpad on TLMM 3" \
	"$(for tp in touchpad@15 touchpad@2c touchpad@38 touchpad@5d; do fdtget -t x "$dtb" "$i2c19/$tp" interrupts-extended 2>/dev/null; done | grep -c "^$tlmm 3 ")" "0"
# smb2360 PMICs: SID 0xa is absent on this board (probe fails); 0x7 (first
# USB-C port's repeater) and 0xb answer and must stay enabled.
spmi=/soc@0/arbiter@c400000/spmi@c432000
expect "absent smb2360 (SID 0xa) disabled" "$(node_status $spmi/pmic@a)" "disabled"
expect "smb2360 SID 0x7 enabled (USB-C 1 repeater)" "$(node_status $spmi/pmic@7)" "okay"
expect "smb2360 SID 0xb enabled" "$(node_status $spmi/pmic@b)" "okay"
# Working hardware must stay enabled.
expect "USB-C 1 controller (usb_1_ss0) enabled" "$(node_status /soc@0/usb@a600000)" "okay"
expect "camera controller (usb_2) enabled" "$(node_status /soc@0/usb@a200000)" "okay"
expect "USB-A controller (multiport) enabled" "$(node_status /soc@0/usb@a400000)" "okay"
expect "GPU enabled" "$(node_status /soc@0/gpu@3d00000)" "okay"
expect "keyboard IRQ on TLMM 67" "$(fdtget -t x "$dtb" /soc@0/geniqup@ac0000/i2c@a84000/keyboard@3a interrupts-extended 2>/dev/null)" "$tlmm 43 8"
expect "touchscreen IRQ on TLMM 51" "$(fdtget -t x "$dtb" /soc@0/geniqup@ac0000/i2c@a80000/touchscreen@10 interrupts-extended 2>/dev/null)" "$tlmm 33 8"
expect "no CRD retimer-2 supplies (TLMM 126)" "$(echo "$dts" | grep -c 'VREG_RTMR2')" "0"
expect "HDMI bridge present" "$(prop /hdmi-bridge compatible)" "realtek,rtd2171"
# HDMI graph: dp2 -> usb_1_ss2 QMP PHY (DP output) -> bridge -> connector.
# Each link is checked in both directions (remote-endpoint phandles).
dp2=/soc@0/display-subsystem@ae00000/displayport-controller@ae9a000
phy=/soc@0/phy@fdf000
ph() { fdtget -t x "$dtb" "$1" phandle 2>/dev/null; }
rem() { fdtget -t x "$dtb" "$1" remote-endpoint 2>/dev/null; }
linked() { # description, endpoint A, endpoint B
	if [ -n "$(ph "$2")" ] && [ "$(rem "$2")" = "$(ph "$3")" ] && [ "$(rem "$3")" = "$(ph "$2")" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1: $2 <-> $3 not linked"; fail=1
	fi
}
expect "dp2 uses the usb_1_ss2 PHY's DP output (QMP_USB43DP_DP_PHY)" "$(fdtget -t x "$dtb" $dp2 phys 2>/dev/null)" "$(ph $phy) 1"
linked "dp2 output <-> PHY DP input (port@2)" $dp2/ports/port@1/endpoint $phy/ports/port@2/endpoint
linked "PHY DP output (port@0/endpoint@0) <-> HDMI bridge input" $phy/ports/port@0/endpoint@0 /hdmi-bridge/ports/port@0/endpoint
linked "HDMI bridge output <-> HDMI connector" /hdmi-bridge/ports/port@1/endpoint /hdmi-connector/port/endpoint
expect "HDMI connector is type A" "$(prop /hdmi-connector type)" "a"
# NORMAL orientation (series 4); <0 1 2 3> (REVERSE) failed link training.
expect "HDMI lane mapping data-lanes = <3 2 1 0>" "$(fdtget -t u "$dtb" $phy/ports/port@0/endpoint@0 data-lanes 2>/dev/null)" "3 2 1 0"
expect "PHY lane mode fixed by DT (no Type-C mode/orientation switch)" \
	"$(fdtget -p "$dtb" $phy 2>/dev/null | grep -cE '^(mode|orientation)-switch$')" "0"
expect "no USB3 endpoint on the HDMI PHY (DP-only mode)" "$(fdtget -l "$dtb" $phy/ports/port@0 2>/dev/null | grep -c 'endpoint@1')" "0"
expect "dp2 link rates RBR..HBR3" "$(fdtget -t u "$dtb" $dp2/ports/port@1/endpoint link-frequencies 2>/dev/null | wc -w)" "8"
expect "HDMI hot-plug pin uses usb2_dp" "$(echo "$dts" | grep -A3 'hdmi-hpd-default-state' | grep -c 'usb2_dp')" "1"
expect "dp2 (HDMI) enabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae9a000)" "okay"
expect "dp0 disabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae90000)" "disabled"
expect "dp1 disabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@ae98000)" "disabled"
expect "eDP (dp3) enabled" "$(node_status /soc@0/display-subsystem@ae00000/displayport-controller@aea0000)" "okay"
expect "camera eUSB2 repeater" "$(echo "$dts" | grep -c 'redriver@4b {')" "1"
expect "audio card enabled" "$(node_status /sound)" "okay"
expect "audio card model" "$(prop /sound model)" "X1E80100-LENOVO-IdeaPad-Slim3-15Q8X10"
expect "two-speaker playback link" "$(fdtget -l "$dtb" /sound 2>/dev/null | grep -c wsa-dai-link)" "1"
expect "no DP audio links (dp0/dp1 off)" "$(fdtget -l "$dtb" /sound 2>/dev/null | grep -c displayport)" "0"
# Fixed paths, not labels: kernel-built DTBs have no __symbols__ table.
# swr3 stays disabled, so its CRD WooferRight/TweeterRight nodes are never bound.
swr0=/soc@0/soundwire@6b10000
expect "speaker SoundWire (swr0) on" "$(node_status $swr0)" "okay"
expect "second amp bus (swr3) off" "$(node_status /soc@0/soundwire@6ab0000)" "disabled"
expect "left speaker prefix" "$(prop $swr0/speaker@0,0 sound-name-prefix)" "SpkrLeft"
expect "right speaker prefix" "$(prop $swr0/speaker@0,1 sound-name-prefix)" "SpkrRight"
expect "left speaker port map" "$(fdtget -t u "$dtb" "$swr0/speaker@0,0" qcom,port-mapping 2>/dev/null)" "1 2 3 7 10 13"
expect "right speaker port map" "$(fdtget -t u "$dtb" "$swr0/speaker@0,1" qcom,port-mapping 2>/dev/null)" "4 5 6 7 11 13"
expect "headset SoundWire (swr1) on" "$(node_status /soc@0/soundwire@6ad0000)" "okay"
# Series 6: CPU zones must throttle before the 115 °C critical shutdown.
# Cluster 0 (cpu0–3) and cluster 1 (cpu4–7) each share one SCMI domain.
cpu0ph=$(fdtget -t x "$dtb" /cpus/cpu@0 phandle 2>/dev/null)
cpu4ph=$(fdtget -t x "$dtb" /cpus/cpu@10000 phandle 2>/dev/null)
c0map=$(fdtget -t x "$dtb" /thermal-zones/cpu0-0-top-thermal/cooling-maps/map0 cooling-device 2>/dev/null)
c1map=$(fdtget -t x "$dtb" /thermal-zones/cpu1-0-top-thermal/cooling-maps/map0 cooling-device 2>/dev/null)
expect "cpu0 top passive trip at 75 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpu0-0-top-thermal/trips/passive temperature 2>/dev/null)" "75000"
expect "cpu0 top passive type" "$(prop /thermal-zones/cpu0-0-top-thermal/trips/passive type)" "passive"
expect "cpu0 bottom passive trip at 75 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpu0-3-btm-thermal/trips/passive temperature 2>/dev/null)" "75000"
expect "cluster 0 passive cools cpu0" "${c0map%% *}" "$cpu0ph"
expect "cluster 0 cooling limit is open" "$(echo "$c0map" | awk '{print $2}')" "ffffffff"
expect "cpu1 top passive trip at 75 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpu1-0-top-thermal/trips/passive temperature 2>/dev/null)" "75000"
expect "cluster 1 passive cools cpu4" "${c1map%% *}" "$cpu4ph"
expect "cpuss0 passive trip at 75 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpuss0-top-thermal/trips/passive temperature 2>/dev/null)" "75000"
expect "cpuss1 passive trip at 75 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpuss1-btm-thermal/trips/passive temperature 2>/dev/null)" "75000"
expect "cpu critical trip still 115 °C" "$(fdtget -t i "$dtb" /thermal-zones/cpu0-0-top-thermal/trips/cpu-critical temperature 2>/dev/null)" "115000"
expect "gpu passive trip lowered to 85 °C" "$(fdtget -t i "$dtb" /thermal-zones/gpuss-0-thermal/trips/trip-point0 temperature 2>/dev/null)" "85000"
expect "gpu critical trip still 115 °C" "$(fdtget -t i "$dtb" /thermal-zones/gpuss-0-thermal/trips/gpu-critical temperature 2>/dev/null)" "115000"
# Purwa deletes GPU zones 4–7. Do not describe trips for sensors that are gone.
expect "no passive trip on deleted gpuss-4" "$(fdtget -t i "$dtb" /thermal-zones/gpuss-4-thermal/trips/trip-point0 temperature 2>/dev/null)" ""

exit $fail
