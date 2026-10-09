#!/bin/bash
# Fetch only the redistributable linux-firmware files this laptop needs:
# Snapdragon X GPU/DSP generics, WCN7850 Wi-Fi (ath12k) and Bluetooth.
# The device-signed blobs (ADSP/CDSP/GPU zap for LENOVO 83N3) are NOT here;
# debondragon-firmware copies those from the owner's Windows install.
# Usage: iso/fetch-firmware.sh <workdir> <dest-lib-firmware>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
dest=$2
fw=$work/linux-firmware

patterns=(
  'qcom/x1e80100/*'
  'qcom/x1p42100/*'
  'qcom/gen70500_*'
  'qcom/gen71500_*'
  'qcom/a740_*'
  'qcom/gmu_gen70500.bin'
  'ath12k/WCN7850/**'
  'qca/hmt*'
  'qca/htbtfw*'
  'qca/htnv*'
  'WHENCE'
  'LICENSE.*'
  'LICENCE.*'
)

if [ ! -d "$fw/.git" ]; then
  git clone --depth 1 --branch "$FIRMWARE_REF" --filter=blob:none --sparse "$FIRMWARE_REPO" "$fw"
fi
git -C "$fw" sparse-checkout set --no-cone "${patterns[@]}"

cd "$fw"
mkdir -p "$dest"
find qcom ath12k qca -type f 2>/dev/null | while read -r f; do
  install -D -m 0644 "$f" "$dest/$f"
done
mkdir -p "$dest/licenses"
cp WHENCE LICENSE.* LICENCE.* "$dest/licenses/" 2>/dev/null || true

# linux-firmware keeps symlinks as "Link:" lines in WHENCE; recreate the
# ones that point inside what we copied.
grep -E '^Link: (qcom|ath12k|qca)/' WHENCE | while read -r _ link _ target; do
  dir=$(dirname "$link")
  if [ -e "$dest/$dir/$target" ] && [ ! -e "$dest/$link" ]; then
    ln -s "$target" "$dest/$link"
  fi
done

du -sh "$dest"
