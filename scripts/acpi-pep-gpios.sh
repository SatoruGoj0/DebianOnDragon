#!/bin/bash
# List the TLMM GPIO actions in the Qualcomm PEP power tables of a
# decompiled DSDT, grouped by the device they belong to. Each line:
#   <device> <pin> <value> [<extra fields>]
# Usage: scripts/acpi-pep-gpios.sh <DSDT.dsl>
set -euo pipefail
awk '
  # PEP device packages start with the device path, e.g. "\\_SB.USB4".
  /^ *"\\\\_SB\.[A-Z0-9_.]+",? *$/ { dev = $0; gsub(/[ ",]/, "", dev) }
  /"TLMMGPIO(_V2)?",/ { want = 1; vals = ""; next }
  want {
    line = $0; gsub(/[ ,]|\/\/.*/, "", line)
    if (line == "Package(0x04)" || line == "Package(0x05)" || line == "Package(0x06)" || line == "{" || line ~ /^Package/) next
    if (line == "}" ) { print dev, vals; want = 0; next }
    vals = vals " " line
  }
' "$1" | awk '{ $2 = sprintf("%d", strtonum($2)); print }' | sort -u
