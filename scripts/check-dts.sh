#!/bin/bash
# Compile the board devicetree against a (sparse) Linux tree without a full
# kernel build. Usage: scripts/check-dts.sh <linux-tree> [out.dtb]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
linux=$1
out=${2:-/tmp/debondragon-check.dtb}
dts=$here/dts/x1p42100-lenovo-ideapad-slim3-15q8x10.dts
qcom=$linux/arch/arm64/boot/dts/qcom

cpp -nostdinc -undef -x assembler-with-cpp -D__DTS__ \
    -I "$qcom" -I "$linux/include" -I "$linux/scripts/dtc/include-prefixes" \
    "$dts" -o "$out.pre"
dtc -@ -I dts -O dtb -i "$qcom" -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size \
    -Wno-unique_unit_address \
    -o "$out" "$out.pre"
echo "OK: $out ($(stat -c %s "$out") bytes)"
fdtget "$out" / model
