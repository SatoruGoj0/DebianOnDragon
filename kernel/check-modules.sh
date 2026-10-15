#!/bin/bash
# Check a built linux-image package: the board DTB is inside, every module
# the 83N3 needs is present (or built in), and module dependencies resolve
# (depmod with -e against the package's own symbol table).
# Usage: kernel/check-modules.sh <linux-image.deb> <kernel-release>
set -uo pipefail
deb=$1
kver=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dpkg-deb -x "$deb" "$tmp"
mods=$tmp/lib/modules/$kver
[ -d "$mods" ] || mods=$tmp/usr/lib/modules/$kver
fail=0

for board in x1p42100-lenovo-ideapad-slim3-15q8x10 x1p42100-lenovo-ideapad-slim3-15q8x10-speakers; do
	dtb=$tmp/usr/lib/linux-image-$kver/qcom/$board.dtb
	if [ -f "$dtb" ]; then echo "ok   $board.dtb in package"; else echo "FAIL $board.dtb missing"; fail=1; fi
done

for m in msm panel-edp pwm_bl leds-qcom-lpg simple-bridge display-connector \
         phy-qcom-qmp-combo i2c-hid-of hid-multitouch i2c-qcom-geni \
         phy-nxp-ptn3222 uvcvideo dwc3-qcom qcom-hamoa-ec ath12k btqca \
         qcom-iris videocc-x1p42100 \
         snd-soc-x1e80100 snd-soc-wcd938x snd-soc-wcd938x-sdw snd-soc-wsa884x \
         snd-soc-lpass-rx-macro snd-soc-lpass-tx-macro snd-soc-lpass-va-macro \
         snd-soc-lpass-wsa-macro soundwire-qcom qcom_q6v5_pas; do
	name=${m//-/_}
	if find "$mods" -name "$m.ko*" -o -name "$name.ko*" | grep -q . ||
	   grep -qE "/($m|$name)\.ko" "$mods/modules.builtin" 2>/dev/null; then
		echo "ok   module $m"
	else
		echo "FAIL module $m not in package"; fail=1
	fi
done

# Unresolved symbols across the package's modules.
map=$(ls "$tmp"/boot/System.map-"$kver" 2>/dev/null)
if [ -n "$map" ]; then
	base=${mods%/lib/modules/*}
	if depmod -b "$base" -e -F "$map" -n "$kver" 2>&1 >/dev/null | grep -i 'unknown symbol\|needs unknown'; then
		echo "FAIL depmod reports unresolved symbols"; fail=1
	else
		echo "ok   depmod: all module symbols resolve"
	fi
else
	echo "warn no System.map in package; depmod check skipped"
fi

exit $fail
