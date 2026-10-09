#!/bin/bash
# Print the full ASL body of one or more Device() blocks from a decompiled DSDT.
# Usage: scripts/acpi-device.sh <DSDT.dsl> NAME [NAME...]
set -euo pipefail
dsl=$1; shift
for name in "$@"; do
  echo "##### $name"
  awk -v want="Device ($name)" '
    !p && index($0, want) { p=1; depth=0 }
    p { print; o=gsub(/\{/,"{"); c=gsub(/\}/,"}"); depth+=o-c; if (seen && depth<=0) exit; if (o) seen=1 }
  ' "$dsl"
done
