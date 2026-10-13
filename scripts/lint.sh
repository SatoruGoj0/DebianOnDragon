#!/bin/bash
# Syntax-check and shellcheck every shell script in the repository.
# Usage: scripts/lint.sh   (needs shellcheck)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
mapfile -t files < <(
	{
		ls build.sh kernel/*.sh iso/*.sh scripts/*.sh support/*.sh
		ls support/root/usr/local/sbin/* support/root/etc/grub.d/* \
		   support/root/etc/kernel/*/*
	} 2>/dev/null | sort -u)
for f in "${files[@]}"; do
	if grep -q $'\r' "$f"; then echo "CRLF line endings: $f"; fail=1; fi
	shell="bash"
	head -1 "$f" | grep -q '/bin/sh' && shell="sh"
	if ! $shell -n "$f"; then echo "syntax error: $f"; fail=1; fi
done
# SC2154: variables provided by grub-mkconfig_lib; SC1091: sourced at runtime.
shellcheck -S warning -e SC2154,SC1091 "${files[@]}" || fail=1
echo "checked ${#files[@]} scripts"
exit $fail
