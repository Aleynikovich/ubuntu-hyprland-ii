#!/usr/bin/env bash
# The only system-wide file this setup creates: the SDDM login entry. The Plasma session is untouched.
# Rollback: sudo rm /usr/share/wayland-sessions/hyprland-ii.desktop
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

W=$PREFIX/session-bin/hyprland-ii-session
[ -x "$W" ] || die "$W missing; run 50-dots first."
F=/usr/share/wayland-sessions/hyprland-ii.desktop

step "Writing $F"
sudo install -d -m 0755 /usr/share/wayland-sessions
sudo tee "$F" >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland (illogical-impulse)
Comment=Hyprland 0.56 + Quickshell, installed in $PREFIX
Exec=$W
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
EOF
cat "$F"
ls /usr/share/xsessions/ /usr/share/wayland-sessions/
ok "Log out and pick \"Hyprland (illogical-impulse)\" in SDDM. Avoid Ctrl+Alt+Fn VT switches inside Hyprland (known crash)."
