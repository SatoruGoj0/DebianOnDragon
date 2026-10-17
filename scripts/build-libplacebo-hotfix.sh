#!/bin/bash
# Build an optional libplacebo 7.349 hotfix package for Moonlight on the 83N3.
#
# Build dependencies (Ubuntu 25.10):
#   sudo apt install git meson ninja-build gcc g++ pkg-config libvulkan-dev \
#     liblcms2-dev libxxhash-dev libshaderc-dev
#
# Usage: scripts/build-libplacebo-hotfix.sh [output-directory]
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/out"}
tmp=$(mktemp -d /tmp/debondragon-libplacebo.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

src=$tmp/libplacebo
build=$tmp/build
pkg=$tmp/pkg
multiarch=$(cc -dumpmachine)
arch=$(dpkg --print-architecture)
version=7.349.0+debondragon1

git clone --quiet --depth 1 --branch v7.349.0 \
	https://github.com/haasn/libplacebo.git "$src"
git -C "$src" apply "$here/userspace/patches/libplacebo-7.349-host-pointer-check.patch"

meson setup "$build" "$src" \
	--prefix=/usr/local \
	--libdir="lib/$multiarch" \
	--buildtype=release \
	-Ddemos=false -Dtests=false -Dbench=false \
	-Dvulkan=enabled -Dopengl=disabled \
	-Dglslang=disabled -Dshaderc=enabled \
	-Dlcms=enabled -Ddovi=disabled -Dlibdovi=disabled
meson compile -C "$build"

install -D -m 0755 "$build/src/libplacebo.so.349" \
	"$pkg/usr/local/lib/$multiarch/libplacebo.so.349"
mkdir -p "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<EOF
Package: debondragon-libplacebo-hotfix
Version: $version
Architecture: $arch
Maintainer: DebOnDragon <noreply@users.noreply.github.com>
Section: libs
Priority: optional
Depends: libplacebo349, libshaderc1
Description: libplacebo host-pointer guard for Moonlight on the 83N3
 Backports the upstream Vulkan host-pointer capability check to Ubuntu's
 libplacebo 7.349 ABI. This prevents Moonlight's Iris decoder probe from
 calling a missing Vulkan function through a null pointer.
EOF
cat > "$pkg/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF
cat > "$pkg/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF
chmod 755 "$pkg/DEBIAN/postinst" "$pkg/DEBIAN/postrm"

mkdir -p "$out"
dpkg-deb --root-owner-group -b "$pkg" \
	"$out/debondragon-libplacebo-hotfix_${version}_${arch}.deb"
