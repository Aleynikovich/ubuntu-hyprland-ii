#!/usr/bin/env bash
# Keep the NVIDIA GPU "warm" so the first window/animation after idle isn't laggy
# Why: the GPU idles at P8 (210 MHz); the first frame after a quiet spell (e.g. spawning foot after a while in VS Code) waits for it to clock up.
#   On AC: persistence daemon + graphics clock floor of ${GPU_MIN_MHZ:-1200} MHz (max stays 3105). On battery: floor released.
#   Re-applied on AC plug/unplug (udev), boot, and resume from sleep.
# Rollback: sudo systemctl disable --now gpu-warm.service; sudo systemctl stop nvidia-persistenced; sudo rm /etc/systemd/system/gpu-warm.service /etc/udev/rules.d/99-gpu-warm.rules /usr/local/sbin/gpu-warm; sudo nvidia-smi -rgc
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
MIN="${GPU_MIN_MHZ:-1200}"

step "gpu-warm script"
sudo tee /usr/local/sbin/gpu-warm >/dev/null <<SCRIPT
#!/bin/sh
# AC online -> lock graphics clocks to $MIN..max, otherwise release
ac=0; for f in /sys/class/power_supply/*/; do [ "\$(cat \$f/type 2>/dev/null)" = Mains ] && [ "\$(cat \$f/online 2>/dev/null)" = 1 ] && ac=1; done
if [ "\$ac" = 1 ]; then
  max=\$(nvidia-smi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits | head -1)
  nvidia-smi -lgc $MIN,\$max
else
  nvidia-smi -rgc
fi
SCRIPT
sudo chmod 755 /usr/local/sbin/gpu-warm

step "systemd unit + udev trigger"
sudo tee /etc/systemd/system/gpu-warm.service >/dev/null <<'UNIT'
[Unit]
Description=Keep NVIDIA GPU clocks warm on AC
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
sleep 1; nvidia-smi --query-gpu=pstate,clocks.gr,power.draw,persistence_mode --format=csv
ok "GPU kept warm on AC."
