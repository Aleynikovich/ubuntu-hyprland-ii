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

step "Check"
ls -l /sys/class/backlight/*/brightness
ok "Backlight is group-writable. After the next login: brightnessctl s 80% && brightnessctl s 100%"
