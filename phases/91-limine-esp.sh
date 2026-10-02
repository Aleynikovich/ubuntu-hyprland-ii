#!/usr/bin/env bash
# Limine boots a static kernel+initrd copy from the ESP (not GRUB): keep it synced with /boot and carry the resume= args
# Rollback: sudo rm /etc/kernel/postinst.d/zz-limine-esp /etc/initramfs/post-update.d/limine-esp
#   and restore /boot/efi/limine.conf + /boot/efi/EFI/limine/limine.conf from the *.bak next to them.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

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
  [ -f "$ESP/vmlinuz" ] && cp -f "$ESP/vmlinuz" "$ESP/vmlinuz.old" && cp -f "$ESP/initrd.img" "$ESP/initrd.img.old"
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

step "Keep the currently-booted kernel as the fallback, then sync the newest"
RUNNING=$(uname -r)
sudo cp -f "/boot/vmlinuz-$RUNNING" "$ESP/vmlinuz.old"
sudo cp -f "/boot/initrd.img-$RUNNING" "$ESP/initrd.img.old"
NEWEST=$(sudo sh -c 'ls /boot/vmlinuz-* | sed "s|.*/vmlinuz-||" | sort -V | tail -1')
sudo /usr/local/sbin/limine-esp-sync "$NEWEST"
# the sync saved the old ESP copy over *.old; put the running kernel back there in case they differed
sudo cp -f "/boot/vmlinuz-$RUNNING" "$ESP/vmlinuz.old"; sudo cp -f "/boot/initrd.img-$RUNNING" "$ESP/initrd.img.old"

step "limine.conf: resume args + fallback entry"
UUID=$(findmnt -no UUID /)
OFFSET=$(sudo filefrag -v /swap.img | awk '$1=="0:" && !s {sub(/\.\.$/,"",$4); print $4; s=1}')
[[ "$UUID" =~ ^[0-9a-f-]+$ && "$OFFSET" =~ ^[0-9]+$ ]] || die "Could not determine resume UUID/offset."
CMD="root=/dev/mapper/ubuntu--vg-ubuntu--lv ro quiet splash resume=UUID=$UUID resume_offset=$OFFSET"
for f in "$ESP/limine.conf" "$ESP/EFI/limine/limine.conf"; do
  [ -f "$f.bak" ] || sudo cp -p "$f" "$f.bak"
  sudo tee "$f" >/dev/null <<EOF
timeout: 5

/Ubuntu ($NEWEST)
    protocol: linux
    kernel_path: boot():/vmlinuz
    module_path: boot():/initrd.img
    cmdline: $CMD

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
