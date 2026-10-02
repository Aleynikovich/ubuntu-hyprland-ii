#!/usr/bin/env bash
# Remove GRUB/shim/os-prober/memtest86+ (the machine boots Limine from the ESP; see phase 91)
# Rollback: sudo apt install grub-efi-amd64 shim-signed memtest86+ os-prober && sudo grub-install
#   Backup of /etc/default/grub and /etc/grub.d: $BACKUP_DIR/grub-etc-*.tar.gz
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

ESP=/boot/efi
cmp -s "$ESP/EFI/BOOT/BOOTX64.EFI" "$ESP/EFI/limine/BOOTX64.EFI" || die "The fallback EFI loader is not Limine; refusing to remove GRUB."
efibootmgr | grep -q 'Limine' || die "No Limine entry in the EFI boot menu; refusing."
[ -f "$ESP/limine.conf" ] && [ -x /usr/local/sbin/limine-esp-sync ] || die "Run phase 91 first."
[ -e "$ESP/vmlinuz" ] && [ -e "$ESP/initrd.img" ] || die "No kernel on the ESP."

PKGS=(grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed grub-common grub2-common shim-signed os-prober memtest86+)
installed=(); for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 && installed+=("$p") || true; done

if [ "${#installed[@]}" -gt 0 ]; then
  step "Backup + purge: ${installed[*]}"
  mkdir -p "$BACKUP_DIR"
  sudo tar czf "$BACKUP_DIR/grub-etc-$(date +%F).tar.gz" /etc/default/grub /etc/grub.d 2>/dev/null || true
  apt-get -s purge "${installed[@]}" | grep -E '^(Remv|Purg)'
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
