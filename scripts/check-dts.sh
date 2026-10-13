#!/bin/bash
# Compile the board devicetrees against a (sparse) Linux tree without a full
# kernel build, and run the DTB assertions on the default board.
# Usage: scripts/check-dts.sh <linux-tree> [outdir]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
linux=$1
outdir=${2:-/tmp/debondragon-check}
qcom=$linux/arch/arm64/boot/dts/qcom
mkdir -p "$outdir"

for dts in "$here"/dts/*.dts; do
	out=$outdir/$(basename "${dts%.dts}").dtb
	cpp -nostdinc -undef -x assembler-with-cpp -D__DTS__ \
	    -I "$here/dts" -I "$qcom" -I "$linux/include" -I "$linux/scripts/dtc/include-prefixes" \
	    "$dts" -o "$out.pre"
	dtc -@ -I dts -O dtb -i "$here/dts" -i "$qcom" \
	    -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size \
	    -Wno-unique_unit_address -Wno-graph_child_address \
	    -o "$out" "$out.pre"
	echo "OK: $out ($(stat -c %s "$out") bytes), sound model: $(fdtget "$out" /sound model)"
done
"$here/scripts/check-dtb.sh" "$outdir/x1p42100-lenovo-ideapad-slim3-15q8x10.dtb"
