#!/usr/bin/env bash
# Limine boots a static kernel+initrd copy from the ESP (not GRUB): keep it synced with /boot and carry the resume= args
# Rollback: sudo rm /etc/kernel/postinst.d/zz-limine-esp /etc/initramfs/post-update.d/limine-esp
#   and restore /boot/efi/limine.conf + /boot/efi/EFI/limine/limine.conf from the *.bak next to them.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

ESP=/boot/efi
[ -f "$ESP/limine.conf" ] || die "No $ESP/limine.conf: this machine does not boot through Limine."

step "Sync hook (kernel upgrades and update-initramfs both refresh the ESP copy; the previous copy is kept as *.old)"
sudo install -d /etc/initramfs/post-update.d
sudo tee /usr/local/sbin/limine-esp-sync >/dev/null <<'EOF'
#!/bin/sh
# Copy /boot/vmlinuz-$1 and /boot/initrd.img-$1 to the ESP where Limine reads them. Usage: limine-esp-sync <version>
set -e
v=$1; ESP=/boot/efi
[ -n "$v" ] && [ -f "/boot/vmlinuz-$v" ] && [ -f "/boot/initrd.img-$v" ] && mountpoint -q "$ESP" || exit 0
# only track the newest installed kernel
newest=$(ls /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
[ "$v" = "$newest" ] || exit 0
if ! cmp -s "/boot/vmlinuz-$v" "$ESP/vmlinuz" || ! cmp -s "/boot/initrd.img-$v" "$ESP/initrd.img"; then
  # keep the previous *kernel* as fallback; a rebuilt initrd of the same kernel must not displace it
  if [ -f "$ESP/vmlinuz" ] && ! cmp -s "/boot/vmlinuz-$v" "$ESP/vmlinuz"; then
    cp -f "$ESP/vmlinuz" "$ESP/vmlinuz.old" && cp -f "$ESP/initrd.img" "$ESP/initrd.img.old"
  fi
  cp -f "/boot/vmlinuz-$v" "$ESP/vmlinuz.new" && cp -f "/boot/initrd.img-$v" "$ESP/initrd.img.new"
  mv -f "$ESP/vmlinuz.new" "$ESP/vmlinuz" && mv -f "$ESP/initrd.img.new" "$ESP/initrd.img"
  sync
  logger -t limine-esp-sync "ESP now boots $v"
fi
EOF
sudo chmod 755 /usr/local/sbin/limine-esp-sync
sudo tee /etc/kernel/postinst.d/zz-limine-esp >/dev/null <<'EOF'
#!/bin/sh
exec /usr/local/sbin/limine-esp-sync "$1"
EOF
sudo tee /etc/initramfs/post-update.d/limine-esp >/dev/null <<'EOF'
#!/bin/sh
exec /usr/local/sbin/limine-esp-sync "$1"
EOF
sudo chmod 755 /etc/kernel/postinst.d/zz-limine-esp /etc/initramfs/post-update.d/limine-esp

step "Sync the newest kernel to the ESP (the previous kernel is kept as the fallback entry)"
RUNNING=$(uname -r)
NEWEST=$(sudo sh -c 'ls /boot/vmlinuz-* | sed "s|.*/vmlinuz-||" | sort -V | tail -1')
if [ ! -f "$ESP/vmlinuz.old" ]; then   # first run: seed the fallback with the kernel that is running now
  sudo cp -f "/boot/vmlinuz-$RUNNING" "$ESP/vmlinuz.old"
  sudo cp -f "/boot/initrd.img-$RUNNING" "$ESP/initrd.img.old"
fi
sudo /usr/local/sbin/limine-esp-sync "$NEWEST"
# label of the fallback entry = the kernel actually stored there
PREV=$(sudo strings "$ESP/vmlinuz.old" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic' | head -1 || true)
[ -n "$PREV" ] || PREV=previous
RUNNING=$PREV

step "limine.conf: resume args + fallback entry"
UUID=$(findmnt -no UUID /)
OFFSET=$(sudo filefrag -v /swap.img | awk '$1=="0:" && !s {sub(/\.\.$/,"",$4); print $4; s=1}')
[[ "$UUID" =~ ^[0-9a-f-]+$ && "$OFFSET" =~ ^[0-9]+$ ]] || die "Could not determine resume UUID/offset."
# s2idle, not S3 "deep": after S3 the NVIDIA driver never re-lights the eDP panel (black even on the text console).
CMD="root=/dev/mapper/ubuntu--vg-ubuntu--lv ro quiet splash mem_sleep_default=s2idle resume=UUID=$UUID resume_offset=$OFFSET"
# Pinned panel EDID (phase 93): main entry only, so the previous-kernel entry stays a clean fallback.
EDID_ARG=""; [ -f /usr/lib/firmware/edid/eDP-1.bin ] && EDID_ARG=" drm.edid_firmware=eDP-1:edid/eDP-1.bin"
for f in "$ESP/limine.conf" "$ESP/EFI/limine/limine.conf"; do
  [ -f "$f.bak" ] || sudo cp -p "$f" "$f.bak"
  sudo tee "$f" >/dev/null <<EOF
timeout: 5

/Ubuntu ($NEWEST)
    protocol: linux
    kernel_path: boot():/vmlinuz
    module_path: boot():/initrd.img
    cmdline: $CMD$EDID_ARG

/Ubuntu ($RUNNING, previous)
    protocol: linux
    kernel_path: boot():/vmlinuz.old
    module_path: boot():/initrd.img.old
    cmdline: $CMD

/Windows Boot Manager
    protocol: efi_chainload
    image_path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
EOF
done
cat "$ESP/limine.conf"
ls -l "$ESP"/vmlinuz* "$ESP"/initrd.img*
ok "Reboot: Limine's menu (5s) should list $NEWEST first; the previous kernel is the second entry."
