#!/usr/bin/env bash
# Lid policy: on AC, or with the shell's "Keep awake" toggle on, closing the lid only blanks the panel; otherwise it hibernates.
# Why: s2idle on this machine keeps fans and keyboard light on and draws ~6 W while "asleep", so suspending on lid close is a bad default.
#   logind ignores the lid; Hyprland's lid-switch binds run ~/.config/hypr/custom/scripts/lid-action.sh.
# Also: Ubuntu's polkit rule (com.ubuntu.desktop.rules) denies hibernate to users; /etc/polkit-1/rules.d/10-hibernate.rules re-allows it for the active local sudo-group session.
# Rollback: sudo rm /usr/local/sbin/lid-unplug-hibernate /etc/systemd/system/lid-unplug-hibernate.service /etc/udev/rules.d/99-lid-unplug-hibernate.rules /etc/polkit-1/rules.d/10-hibernate.rules /etc/systemd/logind.conf.d/10-lid.conf && sudo systemctl kill -s HUP systemd-logind; rm ~/.config/hypr/custom/scripts/lid-action.sh; restore after_sleep_cmd in ~/.config/hypr/hypridle.conf; delete the "Lid:" block from ~/.config/hypr/custom/keybinds.lua
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

SCRIPT="$HOME/.config/hypr/custom/scripts/lid-action.sh"
BINDS="$HOME/.config/hypr/custom/keybinds.lua"

step "logind: ignore the lid"
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/10-lid.conf >/dev/null <<'EOF2'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF2
sudo systemctl kill -s HUP systemd-logind

step "polkit: allow hibernate for the active local admin session"
# Ubuntu: "Disable hibernate by default" in /usr/share/polkit-1/rules.d/com.ubuntu.desktop.rules; "10-" sorts before it and wins.
sudo tee /etc/polkit-1/rules.d/10-hibernate.rules >/dev/null <<'EOF2'
// Ubuntu disables hibernate for users (com.ubuntu.desktop.rules); allow it for the active local admin session (lid policy, phase 98)
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions") &&
        subject.active == true && subject.local == true &&
        subject.isInGroup("sudo")) {
            return polkit.Result.YES;
    }
});
EOF2

step "lid-action.sh"
mkdir -p "$(dirname "$SCRIPT")"
cat > "$SCRIPT" <<'EOF2'
#!/bin/bash
# Lid policy: on AC, or with the shell's "Keep awake" toggle on -> only blank the panel; otherwise hibernate.
# Usage: lid-action.sh close|open   (logind ignores the lid; see /etc/systemd/logind.conf.d/10-lid.conf)
PANEL=eDP-1
STATES="$HOME/.local/state/quickshell/states.json"   # Keep awake = .idle.inhibit (quickshell Idle service)
dpms() { hyprctl dispatch "hl.dsp.dpms({ action = \"$1\", monitor = \"$PANEL\" })" >/dev/null; }

case "$1" in
open) dpms enable ;;
close)
  ac=0
  for f in /sys/class/power_supply/*/; do
    [ "$(cat "$f/type" 2>/dev/null)" = Mains ] && [ "$(cat "$f/online" 2>/dev/null)" = 1 ] && ac=1
  done
  keep=$(jq -r '.idle.inhibit // false' "$STATES" 2>/dev/null)
  if [ "$ac" = 1 ] || [ "$keep" = true ]; then
    dpms disable
  else
    systemctl hibernate
  fi
  ;;
esac
EOF2
chmod +x "$SCRIPT"

step "resume-display.sh (panel on after resume, then lock focus)"
RESUME="$HOME/.config/hypr/custom/scripts/resume-display.sh"
cat > "$RESUME" <<'EOF2'
#!/bin/bash
# After resume (suspend or hibernate): the NVIDIA panel is still dark while Hyprland thinks DPMS is on, so it needs input to wake.
# Force one real off->on modeset once the GPU has settled (more cycles made the lock screen flash), then focus the lock screen. Called from hypridle's after_sleep_cmd.
dpms() { hyprctl dispatch "hl.dsp.dpms({ action = \"$1\", monitor = \"eDP-1\" })" >/dev/null 2>&1; }
sleep 1.5
dpms disable; sleep 0.3; dpms enable
hyprctl dispatch 'hl.dsp.global("quickshell:lockFocus")' >/dev/null 2>&1
EOF2
chmod +x "$RESUME"
IDLE="$HOME/.config/hypr/hypridle.conf"
if [ -f "$IDLE" ] && ! grep -q resume-display.sh "$IDLE"; then
  sed -i 's|^    after_sleep_cmd = .*|    after_sleep_cmd = ~/.config/hypr/custom/scripts/resume-display.sh \& # after-sleep: force the panel on, then focus the lock|' "$IDLE"
  pkill -x hypridle || true; (setsid hypridle >/dev/null 2>&1 &)
fi

step "Hyprland lid-switch binds"
if grep -q 'switch:on:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/lid-action.sh' "$BINDS" 2>/dev/null; then
  echo "binds already present"
else
  cat >> "$BINDS" <<'EOF2'

-- Lid: on AC or with Keep awake on -> panel off only; otherwise hibernate (logind ignores the lid)
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/lid-action.sh close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/lid-action.sh open"), { locked = true })
EOF2
fi

step "Unplug with the lid closed -> hibernate (udev + systemd)"
# lid-action.sh only decides when the lid closes; if AC is pulled while it is already closed, this does the same check on the AC change.
sudo tee /usr/local/sbin/lid-unplug-hibernate >/dev/null <<SCRIPT
#!/bin/sh
# AC change: lid closed + no AC + Keep awake off -> hibernate (same policy as lid-action.sh)
grep -qs closed /proc/acpi/button/lid/*/state || exit 0
for f in /sys/class/power_supply/*/; do
  [ "\$(cat \$f/type 2>/dev/null)" = Mains ] && [ "\$(cat \$f/online 2>/dev/null)" = 1 ] && exit 0
done
[ "\$(jq -r '.idle.inhibit // false' $HOME/.local/state/quickshell/states.json 2>/dev/null)" = true ] && exit 0
exec systemctl hibernate
SCRIPT
sudo chmod 755 /usr/local/sbin/lid-unplug-hibernate
sudo tee /etc/systemd/system/lid-unplug-hibernate.service >/dev/null <<'UNIT'
[Unit]
Description=Hibernate when AC is unplugged with the lid closed

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lid-unplug-hibernate
UNIT
echo 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="lid-unplug-hibernate.service"' | sudo tee /etc/udev/rules.d/99-lid-unplug-hibernate.rules >/dev/null
sudo systemctl daemon-reload
sudo udevadm control --reload

step "Check"
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate
ok "Lid closed: panel off on AC or with Keep awake on, hibernate otherwise."
