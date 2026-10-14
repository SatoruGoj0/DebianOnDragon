#!/bin/sh
# Install DebOnDragon Earbuds for the current user (no root):
#   ~/.local/bin/debondragon-earbuds          the app
#   ~/.local/bin/debondragon-earbuds-status   the Waybar module
#   ~/.local/share/applications/...desktop    app launcher entry
# Needs: gir1.2-gtk-4.0 gir1.2-adw-1 python3-pulsectl python3-gi-cairo
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin=${XDG_BIN_HOME:-$HOME/.local/bin}
apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
mkdir -p "$bin" "$apps"
install -m 0755 "$here/debondragon-earbuds" "$here/debondragon-earbuds-status" "$bin/"
install -m 0644 "$here/org.debondragon.Earbuds.desktop" "$apps/"
sed -i "s|^Exec=.*|Exec=$bin/debondragon-earbuds|" "$apps/org.debondragon.Earbuds.desktop"
update-desktop-database "$apps" 2>/dev/null || true
echo "Installed to $bin and $apps"
