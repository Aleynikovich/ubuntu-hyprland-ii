#!/usr/bin/env bash
# Brightness keys / slider: let the video group write the backlight, and add the user to it.
# Why: Ubuntu's brightnessctl is not setuid and ships no udev rule, /sys/class/backlight/*/brightness is root-only, so the keys and the
#   shell's slider fail with "You should run this program with root privileges". (The backlight itself works: nvidia_0 follows writes.)
#   The group change only applies at the next login (sysfs files can't take ACLs, so there is no stopgap).
# Rollback: sudo rm /etc/udev/rules.d/90-backlight-video.rules; sudo gpasswd -d "$USER" video
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "udev rule: backlight brightness writable by group video"
sudo tee /etc/udev/rules.d/90-backlight-video.rules >/dev/null <<'RULE'
SUBSYSTEM=="backlight", ACTION=="add", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
SUBSYSTEM=="leds", ACTION=="add", KERNEL=="*kbd_backlight*", RUN+="/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="/bin/chmod g+w /sys/class/leds/%k/brightness"
RULE
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=backlight --subsystem-match=leds --action=add

step "$USER -> group video"
if id -nG "$USER" | tr ' ' '\n' | grep -qx video; then echo "already in video"; else sudo usermod -aG video "$USER"; warn "log out and back in for the group to apply"; fi

step "Hold-to-accelerate brightness keys (1% per tap, fast 1% bursts on a long press)"
# Needs the Brightness.qml patch from templates/quickshell-ii/install.sh (IPC `brightness adjust`); the script falls back to brightnessctl.
install -Dm755 "$(dirname "$0")/../templates/scripts/brightness-accel.sh" ~/.config/hypr/custom/scripts/brightness-accel.sh
BINDS="$HOME/.config/hypr/custom/keybinds.lua"
if grep -q brightness-accel.sh "$BINDS" 2>/dev/null; then echo "binds already present"; else
  cat >> "$BINDS" <<'EOF2'

-- Brightness keys: 1% per tap, fast 1% bursts on a long press (replaces the dots' fixed 1% binds)
hl.unbind("XF86MonBrightnessUp")
hl.unbind("XF86MonBrightnessDown")
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/brightness-accel.sh up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/brightness-accel.sh down"), { locked = true, repeating = true })
EOF2
fi

step "Check"
ls -l /sys/class/backlight/*/brightness
ok "Backlight is group-writable. After the next login: brightnessctl s 80% && brightnessctl s 100%"
