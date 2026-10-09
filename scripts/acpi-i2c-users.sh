#!/bin/bash
# List every I2cSerialBus consumer as "controller address enclosing-device".
# Usage: scripts/acpi-i2c-users.sh <DSDT.dsl>
set -euo pipefail
awk '
  /^ *Device \(/ { dev=$0; sub(/.*Device \(/, "", dev); sub(/\).*/, "", dev) }
  /I2cSerialBusV2 \(/ { addr=$0; sub(/.*I2cSerialBusV2 \(/, "", addr); sub(/,.*/, "", addr); pending=1; next }
  pending && /"\\\\_SB\./ { c=$0; sub(/.*"\\\\_SB\./, "", c); sub(/".*/, "", c); print c, addr, dev; pending=0 }
' "$1" | sort | uniq -c
