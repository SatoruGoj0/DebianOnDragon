#!/bin/bash
# Decompile the Windows ACPI tables and summarise the devices that matter
# for writing the 83N3 devicetree (I2C HID, GPIO interrupts, buses).
# Usage: scripts/acpi-extract.sh <dir-with-.aml> <out-dir>
set -euo pipefail
src=$1
out=$2
mkdir -p "$out"
cp "$src"/*.aml "$out"/
cd "$out"
for f in DSDT_*.aml SSDT_*.aml; do iasl -d "$f" >/dev/null 2>&1; done
dsdt=$(ls DSDT_*.dsl)

# Print each Device() block that declares an I2cSerialBus resource, with the
# lines that identify it: _HID/_CID, bus address, controller and GpioInt pins.
awk '
  /^ *Device \(/ { name=$0; buf=""; depth=0; indev=1 }
  indev { buf = buf "\n" $0 }
  indev && /\{/ { depth += gsub(/\{/, "{") }
  indev && /\}/ { depth -= gsub(/\}/, "}"); if (depth <= 0 && buf ~ /I2cSerialBus/) { print "=====" buf; } if (depth <= 0) indev=0 }
' "$dsdt" | grep -E "=====|Device \(|_HID|_CID|_DDN|I2cSerialBus|0x00[0-9A-F]{2}, ControllerInitiated|\"\\\\_SB|GpioInt|^ *0x0[0-9A-F]{3}$|_ADR|Name \(_UID" > i2c-devices.txt || true
echo "wrote $out/i2c-devices.txt ($(grep -c ===== i2c-devices.txt) devices)"
