#!/usr/bin/env bash
# Pin the laptop panel's EDID (kernel firmware override) so a bad EDID re-read on resume can't drop its modes
# Why: after S3 the NVIDIA driver re-probes eDP-1, logs "EDID changed", prunes 3200x2000 as STALE and leaves only 640x480;
#   Hyprland's restore commit (3200x2000@165) then fails -EINVAL forever and the panel stays black.
# Rollback: sudo rm /usr/lib/firmware/edid/eDP-1.bin /etc/initramfs-tools/hooks/edid-firmware; sudo update-initramfs -u;
#   re-run phase 91 after removing EDID_ARG there (or restore /boot/efi/limine.conf.bak).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CONN=$(ls -d /sys/class/drm/card*-eDP-1 2>/dev/null | head -1)
[ -n "$CONN" ] || die "No eDP-1 connector."
FW=/usr/lib/firmware/edid/eDP-1.bin

step "Capture the panel EDID from $CONN (must be a fresh-boot, good read)"
if [ ! -f "$FW" ]; then
  sudo cat "$CONN/edid" > "${TMPDIR:-/tmp}/eDP-1.edid"
  python3 - "${TMPDIR:-/tmp}/eDP-1.edid" <<'PY' || die "EDID from sysfs is not valid (reboot and run again before any suspend)."
import sys
d=open(sys.argv[1],'rb').read()
ok = len(d)>=128 and d[:8]==bytes.fromhex("00ffffffffffff00") and len(d)==128*(d[126]+1) and all(sum(d[i:i+128])%256==0 for i in range(0,len(d),128))
sys.exit(0 if ok else 1)
PY
  sudo install -D -m 0644 "${TMPDIR:-/tmp}/eDP-1.edid" "$FW"
fi
ls -l "$FW"

step "initramfs hook (so the file is there when nvidia-drm probes)"
sudo tee /etc/initramfs-tools/hooks/edid-firmware >/dev/null <<'HOOK'
#!/bin/sh
case "$1" in prereqs) echo; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
copy_file firmware /usr/lib/firmware/edid/eDP-1.bin /usr/lib/firmware/edid/eDP-1.bin
HOOK
sudo chmod 755 /etc/initramfs-tools/hooks/edid-firmware
sudo update-initramfs -u -k all   # the limine-esp-sync hook copies the result to the ESP
lsinitramfs /boot/initrd.img-"$(uname -r)" | grep -i edid

ok "Now run phase 91 (adds drm.edid_firmware= to the main Limine entry only), then reboot."
