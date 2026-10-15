#!/bin/bash
# Build the DebOnDragon kernel as Debian packages, with the 83N3 devicetree.
# Runs natively on arm64 Debian. Usage: kernel/build-kernel.sh <workdir>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/build.conf"
work=$1
src=$work/linux
mkdir -p "$work/kernel-debs"

if [ ! -f "$src/Makefile" ]; then
  git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$src"
  # Without git metadata, setlocalversion adds no "-dirty"/"+" suffix for
  # our added devicetree, so the release is exactly 7.2.0-debondragon.
  rm -rf "$src/.git"
fi

# Firmware may leave Qualcomm remote processors running at boot.  The SMP2P
# series preserves the boot firmware's shared-memory handshake; the remoteproc
# series detects the running processor and attaches to it.  The 83N3 secure
# monitor cannot reset these processors from bare metal, so the final local
# patch provides an attach-only mode selected by qcom,broken-reset.  Pin and
# verify immutable downstream commits rather than following a moving branch.
patchdir=$work/kernel-patches
mkdir -p "$patchdir"
apply_kernel_patch() { # patch, description, optional git-apply arguments
  local patch=$1
  local description=$2
  shift 2

  # The extracted kernel deliberately has no .git directory.  Prevent git
  # from discovering the DebOnDragon checkout above it, which would make
  # `git apply` silently skip every kernel path as outside the current
  # repository subdirectory.
  env GIT_CEILING_DIRECTORIES="$(dirname "$src")" \
    git -C "$src" apply --check "$@" "$patch"
  env GIT_CEILING_DIRECTORIES="$(dirname "$src")" \
    git -C "$src" apply "$@" "$patch"
  echo "applied kernel patch: $description"
}

fetch_remoteproc_patch() { # commit, sha256
  local commit=$1
  local sha=$2
  local patch=$patchdir/$commit.patch
  if [ -f "$patch" ] &&
     printf '%s  %s\n' "$sha" "$patch" | sha256sum -c - >/dev/null 2>&1; then
    echo "using cached kernel patch: $commit"
    return
  fi
  curl --fail --location --silent --show-error --retry 3 \
    --connect-timeout 15 --max-time 120 \
    -o "$patch" \
    "https://github.com/jglathe/linux_ms_dev_kit/commit/$commit.patch"
  printf '%s  %s\n' "$sha" "$patch" | sha256sum -c -
}

# Preserve and negotiate the SMP2P state established by UEFI.  Without this,
# Linux overwrites the outbound state before remoteproc can detect the ADSP.
fetch_remoteproc_patch 6c8ed065898f529c5aac1164ec0ce4384cebfad9 \
  efaea2be44d3346f4a1150de7a198f6a8e25b4742dfd968c87223267630fa169
fetch_remoteproc_patch 27be0bee206ec18a1ae480348bf393f63e3bb5d5 \
  3a726e32edee5ee9b95fc4a59fe618d0278bca1254fb2ecf96e90fdf6b9f6b32
fetch_remoteproc_patch 4a797355f343307b2c0e2ff9cc318baddc4c86e8 \
  f063e8ee61eb0bf34d837780a6f45c513410c6f01cd3934508ef391aef62bd34
fetch_remoteproc_patch 4c8973cacf5fa3152c906099ae45493bd7856cd2 \
  8107a9a3c5e349b88e74ad74e7532a349cc383ee71eedc2e4f20a0eaa0177f63
fetch_remoteproc_patch d0143aa071fd09c1af6a097e71a3d075dd690b2e \
  74951d2c1f9a10c75fe47240dea915d9b90e5a8686df1ec0a879f6730882d392
fetch_remoteproc_patch 5cd74df8d8fc3f926feb135a0849b6c681761fa1 \
  d2bc49170e7ad931117b67ad84a9aa8254671c810566e9f96824add819bdc1d1

fetch_remoteproc_patch c98799e6d0878f4e50abc88a0f33e407b6dd6e06 \
  60df987994f5cc704bb4874b67a7ff17a3452d8316d945091ac885c698b350f5
fetch_remoteproc_patch ec3cf85edd1893f74b1043ff1b19ea71dd4c8906 \
  5a0691b062d59d2cc2a5c7ab00f9d6851950bde26bf58958d6fe473b72e51d0a
fetch_remoteproc_patch d2d2566a88ee0740fdaa1c24493577905c70ebc3 \
  24c743f60126f91228fe927f4a0cd6952e87632e4c6a97f6799d843732d788dc
fetch_remoteproc_patch bcfa27d44c7ddd50c8bac2562d71ba1f84ecb792 \
  2da1cd5132bef918e4fe5d6e15b611d95c690d285f5654c8f836e3b6282a13ac

if grep -q 'qcom_smp2p_scan' "$src/drivers/soc/qcom/smp2p.c" &&
   grep -q 'Reuse existing smem item' "$src/drivers/soc/qcom/smp2p.c"; then
  echo "kernel SMP2P boot-firmware handover series already applied"
else
  apply_kernel_patch "$patchdir/d0143aa071fd09c1af6a097e71a3d075dd690b2e.patch" \
    d0143aa071fd09c1af6a097e71a3d075dd690b2e
  apply_kernel_patch "$patchdir/6c8ed065898f529c5aac1164ec0ce4384cebfad9.patch" \
    6c8ed065898f529c5aac1164ec0ce4384cebfad9
  apply_kernel_patch "$patchdir/27be0bee206ec18a1ae480348bf393f63e3bb5d5.patch" \
    27be0bee206ec18a1ae480348bf393f63e3bb5d5
  apply_kernel_patch "$patchdir/4a797355f343307b2c0e2ff9cc318baddc4c86e8.patch" \
    4a797355f343307b2c0e2ff9cc318baddc4c86e8
  apply_kernel_patch "$patchdir/4c8973cacf5fa3152c906099ae45493bd7856cd2.patch" \
    4c8973cacf5fa3152c906099ae45493bd7856cd2
  apply_kernel_patch "$patchdir/5cd74df8d8fc3f926feb135a0849b6c681761fa1.patch" \
    5cd74df8d8fc3f926feb135a0849b6c681761fa1
fi

if grep -q 'qcom_q6v5_read_smp2p_state' "$src/drivers/remoteproc/qcom_q6v5.c" &&
   grep -q 'RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE' "$src/drivers/remoteproc/qcom_q6v5_pas.c"; then
  echo "kernel remoteproc patch series already applied"
else
  # The first commit predates a small upstream refactor already present in
  # Linux 7.2.  Apply its portable files from the signed commit, then use the
  # equivalent 7.2-context hunk for remoteproc_core.c.
  apply_kernel_patch "$patchdir/c98799e6d0878f4e50abc88a0f33e407b6dd6e06.patch" \
    c98799e6d0878f4e50abc88a0f33e407b6dd6e06 \
    --exclude=drivers/remoteproc/remoteproc_core.c
  apply_kernel_patch "$here/kernel/patches/remoteproc-core-7.2.patch" \
    remoteproc-core-7.2
  apply_kernel_patch "$patchdir/ec3cf85edd1893f74b1043ff1b19ea71dd4c8906.patch" \
    ec3cf85edd1893f74b1043ff1b19ea71dd4c8906
  apply_kernel_patch "$patchdir/d2d2566a88ee0740fdaa1c24493577905c70ebc3.patch" \
    d2d2566a88ee0740fdaa1c24493577905c70ebc3
  # The donor branch already had an older PAS attach implementation.  The
  # signed commit therefore contains context and duplicate callbacks that do
  # not exist in mainline 7.2; this is its equivalent against our clean tree.
  apply_kernel_patch "$here/kernel/patches/qcom-q6v5-pas-attach-7.2.patch" \
    bcfa27d44c7ddd50c8bac2562d71ba1f84ecb792-adapted-for-7.2
fi

if ! grep -q 'qcom_pas_ops_no_reset' "$src/drivers/remoteproc/qcom_q6v5_pas.c"; then
  # Equivalent to downstream commit 1be5a8de07193193f9df17aab35d46c82f842f15,
  # adapted to the preceding Linux 7.2 attach series.
  apply_kernel_patch "$here/kernel/patches/qcom-bare-metal-attach-7.2.patch" \
    1be5a8de07193193f9df17aab35d46c82f842f15-adapted-for-7.2
fi

if ! grep -q 'out_release_pmic_glink' "$src/drivers/soc/qcom/pmic_glink.c"; then
  # Downstream commit 2776716de047 avoids the platform/RPMsg probe race
  # observed when UEFI's ADSP advertises PMIC_RTR very early.
  apply_kernel_patch "$here/kernel/patches/pmic-glink-probe-order-7.2.patch" \
    2776716de047-adapted-for-7.2
fi

if grep -q 'rproc->state == RPROC_ATTACHED' "$src/drivers/remoteproc/remoteproc_sysfs.c"; then
  # pd-mapper derives the service-map directory from this configured name.
  apply_kernel_patch "$here/kernel/patches/remoteproc-attached-firmware-name-7.2.patch" \
    remoteproc-attached-firmware-name-7.2
fi

grep -q 'qcom_q6v5_read_smp2p_state' "$src/drivers/remoteproc/qcom_q6v5.c"
grep -q 'RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE' "$src/drivers/remoteproc/qcom_q6v5_pas.c"
grep -q 'qcom_pas_ops_no_reset' "$src/drivers/remoteproc/qcom_q6v5_pas.c"
grep -q 'Reuse existing smem item' "$src/drivers/soc/qcom/smp2p.c"
grep -q 'out_release_pmic_glink' "$src/drivers/soc/qcom/pmic_glink.c"
! grep -q 'rproc->state == RPROC_ATTACHED' "$src/drivers/remoteproc/remoteproc_sysfs.c"

# Add our board next to the upstream ones.
cp "$here"/dts/*.dts "$here"/dts/*.dtsi "$src/arch/arm64/boot/dts/qcom/"
mk=$src/arch/arm64/boot/dts/qcom/Makefile
for dts in "$here"/dts/*.dts; do
  dtb=$(basename "${dts%.dts}").dtb
  grep -qF "$dtb" "$mk" || echo "dtb-\$(CONFIG_ARCH_QCOM)	+= $dtb" >> "$mk"
done

cd "$src"
make ARCH=arm64 defconfig
# merge_config.sh splits paths on spaces, so merge a copy from the work dir.
cp "$here/kernel/debondragon.config" "$work/debondragon.config"
scripts/kconfig/merge_config.sh -m .config "$work/debondragon.config"
make ARCH=arm64 olddefconfig

# Report fragment options that did not survive olddefconfig (e.g. a
# missing dependency), so a silent drop shows up in the build log.
while IFS= read -r line; do
  case $line in CONFIG_*=*) grep -qxF "$line" .config || echo "warning: $line not applied" ;; esac
done < "$here/kernel/debondragon.config"

"$here/kernel/check-config.sh" .config

# Series > 1 gets its own release suffix so it installs beside older kernels.
series=""
[ "$KERNEL_PKGREV" -gt 1 ] && series="-$KERNEL_PKGREV"
version=$(make -s kernelversion)
make -j"$(nproc)" ARCH=arm64 INSTALL_MOD_STRIP=1 LOCALVERSION="$series" \
  KDEB_PKGVERSION="$version-$KERNEL_PKGREV~debondragon" KDEB_CHANGELOG_DIST="$DEBIAN_SUITE" bindeb-pkg

# The board DTB must still state the facts verified on hardware.
"$here/scripts/check-dtb.sh" "arch/arm64/boot/dts/qcom/$(basename "$BOARD_DTB")"

mv "$work"/linux-image-*.deb "$work"/linux-headers-*.deb "$work/kernel-debs/"
rm -f "$work"/linux-libc-dev_*.deb "$work"/linux-upstream_* "$work"/*.buildinfo "$work"/*.changes

# The kernel release (uname -r) is whatever the image package was built as.
image=""
for deb in "$work"/kernel-debs/linux-image-*.deb; do
  case $deb in *-dbg_*) ;; *) image=$deb; break ;; esac
done
kver=$(basename "$image"); kver=${kver#linux-image-}; kver=${kver%%_*}
echo "$kver" > "$work/kernel-debs/RELEASE"
echo "kernel release: $kver"

# Every driver the board DTB relies on must be in the package, and modules
# must resolve their dependencies.
"$here/kernel/check-modules.sh" "$image" "$kver"
ls -l "$work/kernel-debs"
