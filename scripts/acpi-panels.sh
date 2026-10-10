#!/bin/bash
# Print the Qualcomm panel-config XML blobs embedded in the DSDT, one panel
# per block, keeping the fields relevant to Linux (EDID id, backlight).
# Usage: scripts/acpi-panels.sh <DSDT.aml>
set -uo pipefail
strings -n 3 "$1" | tr -d '\n' | sed 's/<PanelName>/\n<PanelName>/g' | grep '^<PanelName>' | while read -r xml; do
	echo "-----"
	for tag in PanelName PanelDescription BacklightType BacklightPmicControlType \
	           BacklightPMICBankSelect BacklightPMICPWMFrequency BacklightPmicPWMSizeinBits \
	           EDPOverrideMode; do
		v=$(printf '%s' "$xml" | grep -o "<$tag>[^<]*" | head -1 | sed "s/<$tag>//")
		[ -n "$v" ] && echo "$tag=$v"
	done
	# EDID bytes 8-11: vendor + product (little-endian product code).
	edid=$(printf '%s' "$xml" | grep -o '<EDPOverrideEDID>[^<]*' | head -1 | sed 's/<EDPOverrideEDID>//')
	[ -n "$edid" ] && echo "EDID id bytes 8-11: $(echo "$edid" | awk '{print $9, $10, $11, $12}')  name: $(echo "$edid" | grep -o '4C 45 4E 31 3[0-9] [0-9A-F ]*' | head -1 | cut -c1-50)"
done
