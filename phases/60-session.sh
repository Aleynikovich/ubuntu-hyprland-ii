#!/usr/bin/env bash
# System-wide bits: the SDDM login entry and the /opt/MicroTeX link. Other sessions are untouched.
# Rollback: sudo rm /usr/share/wayland-sessions/hyprland-ii.desktop /opt/MicroTeX
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

# The shell's LaTeX renderer (AI sidebar) has /opt/MicroTeX hard-coded; point it at the build in PREFIX.
if [ -x "$PREFIX/opt/MicroTeX/LaTeX" ] && [ "$(readlink /opt/MicroTeX)" != "$PREFIX/opt/MicroTeX" ]; then
  [ -e /opt/MicroTeX ] && [ ! -L /opt/MicroTeX ] && die "/opt/MicroTeX exists and is not our symlink; not touching it."
  sudo ln -sfn "$PREFIX/opt/MicroTeX" /opt/MicroTeX && ls -l /opt/MicroTeX
fi
ls /usr/share/xsessions/ /usr/share/wayland-sessions/
ok "Log out and pick \"Hyprland (illogical-impulse)\" in SDDM. Avoid Ctrl+Alt+Fn VT switches inside Hyprland (known crash)."
