#!/usr/bin/env bash
# Hybrid graphics (BIOS Hybrid mode: Intel iGPU draws the desktop, NVIDIA sleeps until an app is offloaded to it)
# Why: in dGPU-only mode the RTX idles at ~10 W (P4, clocks locked, never D3). In Hybrid it can runtime-suspend to ~0 W:
#   - NVreg_DynamicPowerManagement=0x02 (fine-grained runtime D3; phase 90 set 0x00 for the sleep fix, this overrides it: re-test suspend/hibernate)
#   - SDDM's X server was pinned to NVIDIA by /etc/X11/xorg.conf.d/20-nvidia.conf and held the GPU open for the whole session -> moved aside,
#     AutoAddGPU off so X never grabs the second GPU
#   (phase 95's gpu-warm is Hybrid-aware: no nvidia-smi / persistenced while NVIDIA is asleep; the udev rule that sets power/control=auto ships with the driver.)
# Rollback: sudo rm /etc/modprobe.d/zz-nvidia-hybrid-pm.conf /etc/X11/xorg.conf.d/10-hybrid.conf; sudo mv /etc/X11/xorg.conf.d/20-nvidia.conf.disabled /etc/X11/xorg.conf.d/20-nvidia.conf; reboot
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

lspci | grep -qiE 'VGA.*Intel|Display.*Intel' || die "No Intel iGPU on the PCI bus: set the BIOS graphics mode to Hybrid first."

step "NVIDIA fine-grained runtime power management"
echo 'options nvidia NVreg_DynamicPowerManagement=0x02' | sudo tee /etc/modprobe.d/zz-nvidia-hybrid-pm.conf >/dev/null   # zz: read after nvidia-sleep-fix.conf, last option wins

step "X server (SDDM greeter): don't claim NVIDIA"
[ -f /etc/X11/xorg.conf.d/20-nvidia.conf ] && sudo mv /etc/X11/xorg.conf.d/20-nvidia.conf /etc/X11/xorg.conf.d/20-nvidia.conf.disabled
sudo tee /etc/X11/xorg.conf.d/10-hybrid.conf >/dev/null <<'XORG'
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
XORG

step "Re-apply phase 95 (Hybrid-aware gpu-warm)"
bash "$(dirname "$0")/95-gpu-warm.sh"
ok "Reboot once. Then: maintenance/power-report.sh -> 'gpu runtime PM' should read suspended when idle, and nvidia-smi is not needed."
