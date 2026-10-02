#!/usr/bin/env bash
# Suspend + hibernate that wake up: NVIDIA kernel suspend notifiers, swap file sized and wired for resume, DPMS back on after sleep
# Rollback: sudo rm /etc/modprobe.d/nvidia-sleep-fix.conf; sudo systemctl unmask nvidia-{suspend,resume,hibernate,suspend-then-hibernate}.service; sudo update-initramfs -u. (The swap file just stays bigger.)
# Run phase 91 afterwards: it puts resume=/resume_offset= (derived from the swap file) on the Limine cmdline.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SWAP_FILE=/swap.img
SWAP_GB="${SWAP_GB:-32}"   # must hold the used RAM (+ the compressed image); Isaac Sim can use a lot

step "NVIDIA: kernel suspend notifiers, no runtime D3"
# The systemd nvidia-suspend/resume services (nvidia-sleep.sh: chvt 63, write /proc/driver/nvidia/suspend, chvt back) froze the
# whole machine right after resume here. Driver 595 can save/restore VRAM from the kernel's own suspend path instead; the
# services must then be off (masked, so a driver upgrade does not re-enable them). Runtime D3 is also off (no benefit dGPU-only).
sudo tee /etc/modprobe.d/nvidia-sleep-fix.conf >/dev/null <<'EOF2'
options nvidia NVreg_UseKernelSuspendNotifiers=1 NVreg_DynamicPowerManagement=0x00
EOF2
sudo systemctl mask nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service nvidia-suspend-then-hibernate.service

step "Swap file: ${SWAP_GB}G at $SWAP_FILE"
cur=$(( $(stat -c %s "$SWAP_FILE") / 1024 / 1024 / 1024 ))
if [ "$cur" -lt "$SWAP_GB" ]; then
  avail=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
  [ "$avail" -gt $(( SWAP_GB + MIN_FREE_GB )) ] || die "Only ${avail}G free on /; need ${SWAP_GB}G + ${MIN_FREE_GB}G headroom."
  sudo swapoff "$SWAP_FILE"
  sudo rm -f "$SWAP_FILE"
  sudo fallocate -l "${SWAP_GB}G" "$SWAP_FILE"
  sudo chmod 600 "$SWAP_FILE"
  sudo mkswap "$SWAP_FILE"
  sudo swapon "$SWAP_FILE"
fi
swapon --show

step "Initramfs (resume= itself is on the Limine cmdline: phase 91)"
sudo update-initramfs -u -k all

step "hypridle: switch the display back on after sleep"
H="$HOME/.config/hypr/hypridle.conf"
if [ -f "$H" ] && ! grep -q 'dpms.*enable.*# after-sleep' "$H"; then
  sed -i '/^\s*after_sleep_cmd = /s|^\(\s*\)after_sleep_cmd = \(.*\)$|\1after_sleep_cmd = hyprctl dispatch '"'"'hl.dsp.dpms({ action = "enable" })'"'"' ; \2 # after-sleep|' "$H"
  grep after_sleep_cmd "$H"
fi

command -v etckeeper >/dev/null && sudo etckeeper commit "Phase 90: sleep/hibernate" || true
ok "Run phase 91, then reboot once (new kernel cmdline + nvidia option). Test: systemctl suspend, then systemctl hibernate."
