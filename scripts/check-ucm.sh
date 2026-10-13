#!/bin/bash
# Check that every File/Include path in the DebOnDragon UCM profiles exists,
# either in our package or in Debian's alsa-ucm-conf.
# Usage: scripts/check-ucm.sh <alsa-ucm-conf ucm2 dir, e.g. /usr/share/alsa/ucm2>
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
debian=$1
ours=$here/support/root/usr/share/alsa/ucm2
fail=0
while read -r ref; do
	if [ -f "$ours$ref" ] || [ -f "$debian$ref" ]; then
		echo "ok   $ref"
	else
		echo "FAIL $ref missing"; fail=1
	fi
done < <(grep -rhoE 'File "[^"]+"' "$ours" | sed -E 's/File "([^"]+)"/\1/' | sort -u)
exit $fail
