#!/usr/bin/env bash
# Remove GRUB/shim/os-prober/memtest86+ (the machine boots Limine from the ESP; see phase 91)
# Rollback: sudo apt install grub-efi-amd64 shim-signed memtest86+ os-prober && sudo grub-install
#   Backup of /etc/default/grub and /etc/grub.d: $BACKUP_DIR/grub-etc-*.tar.gz
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_hw

ESP=/boot/efi
cmp -s "$ESP/EFI/BOOT/BOOTX64.EFI" "$ESP/EFI/limine/BOOTX64.EFI" || die "The fallback EFI loader is not Limine; refusing to remove GRUB."
efibootmgr | grep -q 'Limine' || die "No Limine entry in the EFI boot menu; refusing."
[ -f "$ESP/limine.conf" ] && [ -x /usr/local/sbin/limine-esp-sync ] || die "Run phase 91 first."
[ -e "$ESP/vmlinuz" ] && [ -e "$ESP/initrd.img" ] || die "No kernel on the ESP."

PKGS=(grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed grub-common grub2-common shim-signed os-prober memtest86+)
installed=(); for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 && installed+=("$p") || true; done

step "Safety check: Limine must boot on its own before GRUB goes"
efibootmgr | grep -E '^(BootCurrent|BootOrder)|Limine'
first=$(efibootmgr | sed -n 's/^BootOrder: \([0-9A-F]\{4\}\).*/\1/p')
efibootmgr | grep -qE "^Boot$first\*?[[:space:]]+Limine" || warn "Limine is not first in BootOrder (first: Boot$first)."
# ESP copy = newest /boot kernel (vmlinuz-* is root-only, hence sudo cmp)
NEWEST=$(sudo sh -c 'ls /boot/vmlinuz-* | sed "s|.*/vmlinuz-||" | sort -V | tail -1')
sudo cmp -s "/boot/vmlinuz-$NEWEST" "$ESP/vmlinuz" || die "$ESP/vmlinuz is not /boot/vmlinuz-$NEWEST; rerun phase 91."
sudo cmp -s "/boot/initrd.img-$NEWEST" "$ESP/initrd.img" || die "$ESP/initrd.img is not /boot/initrd.img-$NEWEST; rerun phase 91."
echo "ESP vmlinuz + initrd.img = $NEWEST"
# main entry (kernel_path boot():/vmlinuz) in both configs Limine may read; args phases 90/91/93 rely on
UUID=$(findmnt -no UUID /)
OFFSET=$(sudo filefrag -v /swap.img | awk '$1=="0:" && !s {sub(/\.\.$/,"",$4); print $4; s=1}') || die "filefrag /swap.img failed."
[[ "$UUID" =~ ^[0-9a-f-]+$ && "$OFFSET" =~ ^[0-9]+$ ]] || die "Could not determine resume UUID/offset."
need=(mem_sleep_default=s2idle "resume=UUID=$UUID" "resume_offset=$OFFSET")
[ -f /usr/lib/firmware/edid/eDP-1.bin ] && need+=(drm.edid_firmware=eDP-1:edid/eDP-1.bin)
for f in "$ESP/limine.conf" "$ESP/EFI/limine/limine.conf"; do
  [ -f "$f" ] || continue
  entry=$(awk '/^\//{e=0} /kernel_path: *boot\(\):\/vmlinuz$/{e=1} e' "$f")
  grep -q 'module_path: *boot():/initrd.img$' <<<"$entry" || die "$f: main entry does not load boot():/initrd.img."
  cmdline=" $(sed -n 's/^\s*cmdline: *//p' <<<"$entry") "
  for a in "${need[@]}"; do [[ "$cmdline" == *" $a "* ]] || die "$f: main entry cmdline lacks $a; rerun phase 91."; done
  echo "$f: OK (${need[*]})"
done

if [ "${#installed[@]}" -gt 0 ]; then
  step "Purge list"
  apt-get -s purge "${installed[@]}" | grep -E '^(Remv|Purg)'
  confirm "Limine checks passed. Purge the packages above (removes GRUB + the shim Secure Boot chain)?" || die "Aborted; nothing removed."
  step "Backup + purge: ${installed[*]}"
  mkdir -p "$BACKUP_DIR"
  sudo tar czf "$BACKUP_DIR/grub-etc-$(date +%F).tar.gz" /etc/default/grub /etc/grub.d 2>/dev/null || true
  # shim-signed / grub-efi-amd64-signed are marked Essential (they are the Secure Boot chain); Limine replaces it here.
  sudo apt-get purge -y --allow-remove-essential "${installed[@]}"
fi

step "Stale GRUB leftovers"
n=$(efibootmgr | sed -n 's/^Boot\([0-9A-F]\{4\}\)\* ubuntu\s.*shimx64.*/\1/p' | head -1)
[ -z "$n" ] || sudo efibootmgr -b "$n" -B
sudo rm -rf "$ESP/EFI/ubuntu" /boot/grub
efibootmgr | head -4
ls "$ESP/EFI"
ok "GRUB is gone; Limine boots from $ESP."
