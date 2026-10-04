#!/usr/bin/env bash
# Keep GPU + CPU "warm" on AC so the first window/animation after idle isn't laggy
# Why: the GPU idles at P8 (210 MHz); the first frame after a quiet spell (e.g. spawning foot after a while in VS Code) waits for it to clock up.
#   On AC: persistence daemon + graphics clock floor of ${GPU_MIN_MHZ:-1200} MHz (max stays 3105) + memory clock floor of ${GPU_MEM_MIN_MHZ:-6001} MHz
#   (max 8001; the memory clock otherwise idles at 810 and the first blur/animation frame waits for it). On battery: floors released.
#   Hybrid BIOS mode (Intel iGPU on the PCI bus): the iGPU gets a ${IGPU_MIN_MHZ:-900} MHz floor on AC instead and NVIDIA is left alone so it can sleep (see docs/hybrid-graphics.md).
#   Re-applied on AC plug/unplug (udev), boot, and resume from sleep.
# Also sets power profile performance/balanced and CPU governor performance/powersave (Isaac warns on a powersave governor).
# Rollback: sudo systemctl disable --now gpu-warm.service; sudo systemctl stop nvidia-persistenced; sudo rm /etc/systemd/system/gpu-warm.service /etc/udev/rules.d/99-gpu-warm.rules /usr/local/sbin/gpu-warm; sudo nvidia-smi -rgc; sudo nvidia-smi -rmc
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw
MIN="${GPU_MIN_MHZ:-1200}"
IGPU_MIN="${IGPU_MIN_MHZ:-900}"       # Hybrid: Intel iGPU floor on AC (its max is ~1650)
MEM_MIN="${GPU_MEM_MIN_MHZ:-6001}"   # a supported memory clock: nvidia-smi -q -d SUPPORTED_CLOCKS (405 810 6001 7001 8001)

step "gpu-warm script"
sudo tee /usr/local/sbin/gpu-warm >/dev/null <<SCRIPT
#!/bin/sh
# AC online -> performance profile/governor + GPU clock floors; battery -> release, balanced/powersave.
# Which GPU gets the floors depends on the BIOS graphics mode, decided here at run time (an Intel iGPU on the PCI bus = Hybrid):
#   dGPU-only (MUX): NVIDIA draws the desktop -> graphics floor $MIN..max, memory floor $MEM_MIN..max, nvidia-persistenced running.
#   Hybrid: the iGPU draws the desktop -> iGPU floor $IGPU_MIN MHz on AC. NVIDIA is left alone (nvidia-smi and persistenced would
#   wake it / pin it awake): its clock locks are only released if it is awake, and it runtime-suspends (D3) when nothing uses it.
ac=0; for f in /sys/class/power_supply/*/; do [ "\$(cat \$f/type 2>/dev/null)" = Mains ] && [ "\$(cat \$f/online 2>/dev/null)" = 1 ] && ac=1; done
hybrid=0; for d in /sys/bus/pci/devices/*; do [ "\$(cat \$d/vendor)" = 0x8086 ] && case "\$(cat \$d/class)" in 0x03*) hybrid=1;; esac; done
nv() { # nvidia-smi only when the dGPU drives the desktop, or is already awake in hybrid (don't wake a suspended GPU)
  [ "\$hybrid" = 0 ] || [ "\$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)" = active ] || return 0
  nvidia-smi "\$@"
}
pp() { for i in 1 2 3 4 5; do powerprofilesctl set \$1 2>/dev/null && return; sleep 1; done; }   # retry: power-profiles-daemon answers "busy" when two udev AC events race
igpu() { for g in /sys/class/drm/card[0-9]/gt_min_freq_mhz; do [ -w "\$g" ] || continue; d=\$(dirname \$g); [ "\$(cat \$d/device/vendor)" = 0x8086 ] || continue
  if [ "\$1" = floor ]; then echo $IGPU_MIN > \$g; else cat \$d/gt_RPn_freq_mhz > \$g; fi; done; }
if [ "\$hybrid" = 1 ]; then systemctl stop nvidia-persistenced 2>/dev/null; else systemctl start nvidia-persistenced 2>/dev/null; fi
if [ "\$ac" = 1 ]; then
  if [ "\$hybrid" = 0 ]; then
    max=\$(nvidia-smi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits | head -1)
    nvidia-smi -lgc $MIN,\$max
    mmax=\$(nvidia-smi --query-gpu=clocks.max.memory --format=csv,noheader,nounits | head -1)
    nvidia-smi -lmc $MEM_MIN,\$mmax
  else igpu floor; fi
  pp performance
  for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > \$g; done
else
  nv -rgc
  nv -rmc
  [ "\$hybrid" = 1 ] && igpu release
  pp balanced
  for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > \$g; done
fi
SCRIPT
sudo chmod 755 /usr/local/sbin/gpu-warm

step "systemd unit + udev trigger"
sudo tee /etc/systemd/system/gpu-warm.service >/dev/null <<'UNIT'
[Unit]
Description=Keep GPU/CPU clocks warm on AC
Wants=nvidia-persistenced.service
After=nvidia-persistenced.service systemd-suspend.service systemd-hibernate.service systemd-suspend-then-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gpu-warm

[Install]
WantedBy=multi-user.target suspend.target hibernate.target suspend-then-hibernate.target
UNIT
echo 'SUBSYSTEM=="power_supply", ATTR{type}=="Mains", TAG+="systemd", ENV{SYSTEMD_WANTS}+="gpu-warm.service"' | sudo tee /etc/udev/rules.d/99-gpu-warm.rules >/dev/null
sudo systemctl daemon-reload
sudo udevadm control --reload
# nvidia-persistenced is a static unit: pulled in via Wants= in gpu-warm.service
sudo systemctl enable gpu-warm.service
sudo systemctl restart gpu-warm.service

step "Check"
sleep 1
if lspci | grep -qiE 'VGA.*Intel|Display.*Intel'; then   # Hybrid: nvidia-smi would wake the sleeping GPU
  echo "Hybrid: iGPU floor $(cat /sys/class/drm/card[0-9]/gt_min_freq_mhz | tr '\n' ' ')MHz on AC; NVIDIA runtime status: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status)"
else
  nvidia-smi --query-gpu=pstate,clocks.gr,power.draw,persistence_mode --format=csv
fi
ok "Clocks set for the current power source (AC: floors up; battery: released)."
