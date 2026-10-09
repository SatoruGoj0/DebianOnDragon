#!/bin/bash
# Sparse-clone just the parts of the Linux tree needed to build Qualcomm DTBs.
# Usage: scripts/fetch-dts-tree.sh <dest> [ref]
set -euo pipefail
dest=$1
ref=${2:-v7.2}
if [ ! -d "$dest/.git" ]; then
  git clone --depth 1 --branch "$ref" --filter=blob:none --sparse \
    https://github.com/torvalds/linux.git "$dest"
fi
git -C "$dest" sparse-checkout set arch/arm64/boot/dts/qcom include/dt-bindings \
  include/uapi/linux scripts/dtc/include-prefixes
git -C "$dest" log -1 --format='%h %d'
