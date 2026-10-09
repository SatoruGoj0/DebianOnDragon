#!/bin/bash
# One line per ACPI Device(): name, _HID, first MMIO base and _STA hint.
# Usage: scripts/acpi-summary.sh <DSDT.dsl>
set -euo pipefail
awk '
  function flush() { if (name != "") printf "%-6s %-12s %-12s %s\n", name, hid, base, uid; }
  /^ *Device \(/ { flush(); name=$0; sub(/.*Device \(/, "", name); sub(/\).*/, "", name); hid="-"; base="-"; uid=""; want=0; next }
  /Name \(_HID,/ && hid=="-" { hid=$0; sub(/.*_HID, /, "", hid); sub(/\).*/, "", hid); gsub(/"/, "", hid); sub(/ .*/, "", hid) }
  /Name \(_UID,/ && uid=="" { uid=$0; sub(/.*_UID, /, "", uid); sub(/\).*/, "", uid); uid="uid=" uid }
  /Memory32Fixed|QWordMemory/ && base=="-" { want=1; next }
  want && /0x[0-9A-Fa-f]+,/ { v=$0; sub(/^ */, "", v); sub(/,.*/, "", v); if (v !~ /^0x0+$/ || want>1) { base=v; want=0 } else want++ }
  END { flush() }
' "$1"
